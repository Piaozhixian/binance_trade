require 'binance'
require 'dotenv'
Dotenv.load

# Create a new client instance.
# If the APIs do not require the keys, (e.g. market data), key and secret can be omitted.
client = Binance::Spot.new(key: ENV['KEY'], secret: ENV['SECRET'])

# Send a request to get account information
puts client.account