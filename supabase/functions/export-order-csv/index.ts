// supabase/functions/export-order-csv/index.ts

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface ExportRequest {
  order_id: string;
  format?: 'detailed' | 'summary';
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const { order_id, format = 'detailed' }: ExportRequest = await req.json()

    if (!order_id) {
      throw new Error('order_id é obrigatório')
    }

    const { data: orderData, error: orderError } = await supabaseClient
      .rpc('get_order_details', { p_order_id: order_id })

    if (orderError) {
      throw new Error(`Erro ao buscar pedido: ${orderError.message}`)
    }

    if (!orderData) {
      throw new Error('Pedido não encontrado')
    }

    const order = orderData.order
    const customer = orderData.customer
    const address = orderData.address
    const items = orderData.items || []

    let csvContent: string

    if (format === 'summary') {
      csvContent = generateSummaryCSV(order, customer, address, items)
    } else {
      csvContent = generateDetailedCSV(order, customer, address, items)
    }

    return new Response(csvContent, {
      headers: {
        ...corsHeaders,
        'Content-Type': 'text/csv; charset=utf-8',
        'Content-Disposition': `attachment; filename="pedido_${order.order_number}.csv"`,
      },
      status: 200,
    })

  } catch (error) {
    console.error('Erro:', error)
    return new Response(
      JSON.stringify({
        success: false,
        error: error.message
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      }
    )
  }
})

function generateDetailedCSV(order: any, customer: any, address: any, items: any[]): string {
  let csv = '\uFEFF'
  
  csv += 'INFORMAÇÕES DO PEDIDO\n'
  csv += 'Número do Pedido,Status,Data,Valor Total,Método de Pagamento\n'
  csv += `${escapeCSV(order.order_number)},${escapeCSV(getStatusLabel(order.status))},${formatDate(order.created_at)},${formatCurrency(order.total_amount)},${escapeCSV(order.payment_method || 'N/A')}\n`
  csv += '\n'

  csv += 'INFORMAÇÕES DO CLIENTE\n'
  csv += 'Nome,Email,Telefone,CPF\n'
  csv += `${escapeCSV(customer?.full_name || 'N/A')},${escapeCSV(customer?.email || 'N/A')},${escapeCSV(customer?.phone || 'N/A')},${escapeCSV(customer?.cpf || 'N/A')}\n`
  csv += '\n'

  if (address) {
    csv += 'ENDEREÇO DE ENTREGA\n'
    csv += 'Rua,Número,Complemento,Bairro,Cidade,Estado,CEP\n'
    csv += `${escapeCSV(address.street)},${escapeCSV(address.number)},${escapeCSV(address.complement || '')},${escapeCSV(address.neighborhood)},${escapeCSV(address.city)},${escapeCSV(address.state)},${escapeCSV(address.zip_code)}\n`
    csv += '\n'
  }

  csv += 'ITENS DO PEDIDO\n'
  csv += 'Produto,Quantidade,Preço Unitário,Subtotal\n'
  
  items.forEach(item => {
    csv += `${escapeCSV(item.product_name)},${item.quantity},${formatCurrency(item.unit_price)},${formatCurrency(item.subtotal)}\n`
  })
  
  csv += '\n'
  csv += `TOTAL GERAL,,,${formatCurrency(order.total_amount)}\n`

  return csv
}

function generateSummaryCSV(order: any, customer: any, address: any, items: any[]): string {
  let csv = '\uFEFF'
  
  csv += 'Pedido,Cliente,Data,Status,Produto,Quantidade,Preço Unit.,Subtotal\n'
  
  items.forEach(item => {
    csv += `${escapeCSV(order.order_number)},`
    csv += `${escapeCSV(customer?.full_name || 'N/A')},`
    csv += `${formatDate(order.created_at)},`
    csv += `${escapeCSV(getStatusLabel(order.status))},`
    csv += `${escapeCSV(item.product_name)},`
    csv += `${item.quantity},`
    csv += `${formatCurrency(item.unit_price)},`
    csv += `${formatCurrency(item.subtotal)}\n`
  })

  return csv
}

function escapeCSV(value: string): string {
  if (value === null || value === undefined) {
    return ''
  }
  
  const stringValue = String(value)
  
  if (stringValue.includes(',') || stringValue.includes('"') || stringValue.includes('\n')) {
    return `${stringValue.replace(/"/g, '""')}"`
  }
  
  return stringValue
}

function formatDate(dateString: string): string {
  const date = new Date(dateString)
  return date.toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  })
}

function formatCurrency(value: any): string {
  const numValue = parseFloat(value)
  return `R$ ${numValue.toFixed(2).replace('.', ',')}`
}

function getStatusLabel(status: string): string {
  const labels: { [key: string]: string } = {
    'pending': 'Pendente',
    'confirmed': 'Confirmado',
    'processing': 'Em Processamento',
    'shipped': 'Enviado',
    'delivered': 'Entregue',
    'cancelled': 'Cancelado'
  }
  return labels[status] || status
}