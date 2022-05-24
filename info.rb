require 'binance'
require 'dotenv'
require 'slack/incoming/webhooks'

Dotenv.load

SYMBOL = 'BNBBUSD'

client = Binance::Spot.new(key: ENV['KEY'], secret: ENV['SECRET'])
slack = Slack::Incoming::Webhooks.new ENV['WEBHOOK_URL']

loop do
  before_price = client.ticker_24hr(symbol: SYMBOL)[:lastPrice].to_f
  time_before = Time.now.strftime('%Y/%m/%d %H:%M:%S')
  p "#{time_before}: #{before_price}"
  sleep 30 * 60
  begin
    last_price = client.ticker_24hr(symbol: SYMBOL)[:lastPrice].to_f
    time = Time.now.strftime('%Y/%m/%d %H:%M:%S')

    p "#{time}: #{last_price}"
    percent = last_price / before_price
    p "Percent: #{percent}"
    if percent < 0.98
      slack.post "-----\n#{time_before}: #{before_price}\n#{time}: #{last_price}\n`-#{((1 - percent) * 100).round(2)}%`"
    end
  rescue StandardError => e
    slack.post e.to_s
  end
end
