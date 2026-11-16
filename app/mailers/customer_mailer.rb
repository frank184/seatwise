class CustomerMailer < ApplicationMailer
  def sign_in_code(customer, code)
    @customer = customer
    @code = code

    mail(to: customer.email, subject: "Your Seatwise sign-in code")
  end
end
