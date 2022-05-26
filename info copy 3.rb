require 'binance'
require 'dotenv'
require 'slack/incoming/webhooks'

Dotenv.load

SYMBOL = 'SANDBUSD'

client = Binance::Spot.new(key: ENV['KEY'], secret: ENV['SECRET'])
slack = Slack::Incoming::Webhooks.new ENV['WEBHOOK_URL']

date = Date.today
slack.post "=====#{date}====="

loop do
  if date != Date.today
    date = Date.today

    slack.post "=====#{date}====="
  end
  before_price = client.ticker_24hr(symbol: SYMBOL)[:lastPrice].to_f

  time_before = Time.now.strftime('%H:%M')
  p "#{time_before}: #{before_price}"
  sleep 10 * 60
  begin
    last_price = client.ticker_24hr(symbol: SYMBOL)[:lastPrice].to_f
    time = Time.now.strftime('%H:%M')

    p "#{time}: #{last_price}"
    percent = last_price / before_price
    p "Percent: #{percent}"
    if percent < 0.99
      slack.post "<!channel>\n#{SYMBOL}:\n#{time_before} | *#{before_price}*\n#{time} | *#{last_price}*\n` #{((percent - 1) * 100).round(2)}%`"
    else
      num = percent - 1
      if num.negative?
        slack.post "#{SYMBOL}:\n#{time_before} | *#{before_price}*\n#{time} | *#{last_price}*\n`#{((percent - 1) * 100).round(2)}%`"
      else
        slack.post "#{SYMBOL}:\n#{time_before} | *#{before_price}*\n#{time} | *#{last_price}*\n`+#{((percent - 1) * 100).round(2)}%`"

      end
    end
  rescue StandardError => e
    slack.post e.to_s
  end
end
