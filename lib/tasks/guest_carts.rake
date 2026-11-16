namespace :guest_carts do
  desc "Remove expired guest carts without deleting reservations or customers"
  task cleanup: :environment do
    puts "Removed #{GuestCart.cleanup_expired!} expired guest carts"
  end
end
