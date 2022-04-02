export PACKAGE_NAME = if module.id.startsWith('/node_modules/meteor/') then module.id.split('/')[3] else null

export SIGNATURE_HEADER_NAME = 'x-signature'

export WEBHOOK_EVENTS = [
  # 'ORDER_PAID'
  # 'ORDER_UNPAID'
  # 'PAYMENT_PENDING'
  'PAYMENT_APPROVED'
  'PAYMENT_CAPTURED'
  'PAYMENT_CANCELLED'
  'PAYMENT_DECLINED'
  # 'REFUND_PENDING'
  'REFUND_APPROVED'
  'REFUND_DECLINED'
]
