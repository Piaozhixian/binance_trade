require 'binance'
require 'dotenv'
require 'slack/incoming/webhooks'

Dotenv.load

SYMBOL = 'BNBBUSD'

client = Binance::Spot.new(key: ENV['KEY'], secret: ENV['SECRET'])
slack = Slack::Incoming::Webhooks.new ENV['WEBHOOK_URL']

begin
  info = client.account_snapshot(type: 'SPOT')
  last_price = client.ticker_24hr(symbol: 'BTCUSDT')[:lastPrice].to_f

  balance = info[:snapshotVos].last[:data][:totalAssetOfBtc].to_f * last_price
  p "Balance: #{balance.round(2)} USD"
rescue StandardError => e
  slack.post e.to_s
end
