json.data do
  json.id "development"

  json.payment_provider do
    json.id "development-stripe"
    json.provider_key "stripe"
    json.enabled @payment_provider.enabled?
    json.publishable_key(@payment_provider.enabled? ? @payment_provider.publishable_key : nil)
  end
end
