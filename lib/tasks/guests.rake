namespace :guests do
  desc "Remove expired guest sessions without deleting reservations or customers"
  task cleanup: :environment do
    puts "Removed #{Guest.cleanup_expired!} expired guests"
  end
end
