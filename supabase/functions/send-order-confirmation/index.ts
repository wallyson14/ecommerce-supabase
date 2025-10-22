// supabase/functions/send-order-confirmation/index.ts

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface OrderEmailPayload {
  order_id: string;
  customer_email?: string;
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

    const { order_id, customer_email }: OrderEmailPayload = await req.json()

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
    const items = orderData.items

    const toEmail = customer_email || customer?.email

    if (!toEmail) {
      throw new Error('Email do cliente não encontrado')
    }

    const emailHTML = generateOrderEmailHTML(order, customer, address, items)

    const resendApiKey = Deno.env.get('RESEND_API_KEY')
    
    if (resendApiKey) {
      const emailResponse = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${resendApiKey}`,
        },
        body: JSON.stringify({
          from: 'E-commerce <noreply@seudominio.com>',
          to: [toEmail],
          subject: `Confirmação de Pedido #${order.order_number}`,
          html: emailHTML,
        }),
      })

      if (!emailResponse.ok) {
        const errorData = await emailResponse.text()
        throw new Error(`Erro ao enviar email: ${errorData}`)
      }

      const emailResult = await emailResponse.json()
      console.log('Email enviado:', emailResult)
    } else {
      console.log('Email seria enviado para:', toEmail)
      console.log('Conteúdo:', emailHTML)
    }

    return new Response(
      JSON.stringify({
        success: true,
        message: 'Email de confirmação enviado com sucesso',
        order_id: order_id,
        sent_to: toEmail
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      }
    )

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

function generateOrderEmailHTML(order: any, customer: any, address: any, items: any[]): string {
  const itemsHTML = items.map(item => `
    <tr>
      <td style="padding: 10px; border-bottom: 1px solid #eee;">${item.product_name}</td>
      <td style="padding: 10px; border-bottom: 1px solid #eee; text-align: center;">${item.quantity}</td>
      <td style="padding: 10px; border-bottom: 1px solid #eee; text-align: right;">R$ ${parseFloat(item.unit_price).toFixed(2)}</td>
      <td style="padding: 10px; border-bottom: 1px solid #eee; text-align: right;">R$ ${parseFloat(item.subtotal).toFixed(2)}</td>
    </tr>
  `).join('')

  const addressHTML = address ? `
    ${address.street}, ${address.number}${address.complement ? ' - ' + address.complement : ''}<br>
    ${address.neighborhood} - ${address.city}/${address.state}<br>
    CEP: ${address.zip_code}
  ` : 'Endereço não informado'

  return `
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Confirmação de Pedido</title>
    </head>
    <body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
      <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding: 30px; text-align: center; border-radius: 10px 10px 0 0;">
        <h1 style="color: white; margin: 0;">Pedido Confirmado! 🎉</h1>
      </div>
      
      <div style="background: #f9f9f9; padding: 30px; border-radius: 0 0 10px 10px;">
        <p style="font-size: 16px;">Olá <strong>${customer?.full_name || 'Cliente'}</strong>,</p>
        
        <p>Seu pedido foi confirmado com sucesso! Segue abaixo os detalhes:</p>
        
        <div style="background: white; padding: 20px; border-radius: 8px; margin: 20px 0; box-shadow: 0 2px 4px rgba(0,0,0,0.1);">
          <h2 style="margin-top: 0; color: #667eea;">Pedido #${order.order_number}</h2>
          <p><strong>Data:</strong> ${new Date(order.created_at).toLocaleDateString('pt-BR')}</p>
          <p><strong>Status:</strong> <span style="background: #4CAF50; color: white; padding: 5px 10px; border-radius: 5px;">${getStatusLabel(order.status)}</span></p>
        </div>
        
        <h3 style="color: #667eea;">Itens do Pedido:</h3>
        <table style="width: 100%; border-collapse: collapse; background: white; border-radius: 8px; overflow: hidden; box-shadow: 0 2px 4px rgba(0,0,0,0.1);">
          <thead>
            <tr style="background: #667eea; color: white;">
              <th style="padding: 12px; text-align: left;">Produto</th>
              <th style="padding: 12px; text-align: center;">Qtd</th>
              <th style="padding: 12px; text-align: right;">Preço Unit.</th>
              <th style="padding: 12px; text-align: right;">Subtotal</th>
            </tr>
          </thead>
          <tbody>
            ${itemsHTML}
          </tbody>
          <tfoot>
            <tr style="background: #f5f5f5; font-weight: bold;">
              <td colspan="3" style="padding: 15px; text-align: right;">TOTAL:</td>
              <td style="padding: 15px; text-align: right; color: #667eea; font-size: 18px;">R$ ${parseFloat(order.total_amount).toFixed(2)}</td>
            </tr>
          </tfoot>
        </table>
        
        <div style="background: white; padding: 20px; border-radius: 8px; margin: 20px 0; box-shadow: 0 2px 4px rgba(0,0,0,0.1);">
          <h3 style="margin-top: 0; color: #667eea;">Endereço de Entrega:</h3>
          <p style="margin: 0; line-height: 1.8;">${addressHTML}</p>
        </div>
        
        <p style="margin-top: 30px; padding-top: 20px; border-top: 2px solid #eee; text-align: center; color: #666;">
          Obrigado por comprar conosco! 💙<br>
          Em caso de dúvidas, entre em contato através do nosso suporte.
        </p>
      </div>
    </body>
    </html>
  `
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