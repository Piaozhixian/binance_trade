require 'binance'
require 'dotenv'
require 'slack/incoming/webhooks'

Dotenv.load

INTERVAL_TIME_CALC_AVG = 5
INTERVAL_TIME_DO = 60

QUANTITY_BNB = 0.025
QUANTITY_BUSD = 12
SYMBOL = 'BNBBUSD'
SELL_ORDER_MAX = 50
BUY_ORDER_MAX = 50

client = Binance::Spot.new(key: ENV['KEY'], secret: ENV['SECRET'])
slack = Slack::Incoming::Webhooks.new ENV['WEBHOOK_URL']

def can_sell?(free_balance_bnb, sell_orders)
  return false if sell_orders.count >= SELL_ORDER_MAX

  free_balance_bnb > QUANTITY_BNB
end

def can_buy?(free_balance_busd, buy_orders)
  return false if buy_orders.count >= BUY_ORDER_MAX

  free_balance_busd > QUANTITY_BUSD
end

# sell注文が多い時sell_priceとbuy_priceを上げる
# sell注文が少ない時sell_priceとbuy_priceを上げる
def calc_price(avg_price, buy_orders, sell_orders)
  sell_rate = 0.5
  if (buy_orders.count + sell_orders.count) > 3
    sell_rate = sell_orders.count.to_f / (buy_orders.count + sell_orders.count)
  end
  p "Sell rate: #{sell_rate}"
  sell_price = nil
  buy_price = nil

  if sell_rate >= 0.7
    sell_price = avg_price * 1.001
    buy_price = avg_price * 0.997
  elsif sell_rate <= 0.3
    sell_price = avg_price * 1.0012
    buy_price = avg_price * 0.9999
  else
    sell_price = avg_price * 1.001
    buy_price = avg_price * 0.999
  end
  { sell_price: sell_price, buy_price: buy_price }
end

while true
  begin
    p '===== START ====='
    p Time.now
    prices = []

    balance_bnb = client.account[:balances].select { |bal| bal[:asset] == 'BNB' }.first
    free_balance_bnb = balance_bnb[:free].to_f
    locked_balance_bnb = balance_bnb[:locked].to_f
    balance_busd = client.account[:balances].select { |bal| bal[:asset] == 'BUSD' }.first
    free_balance_busd = balance_busd[:free].to_f
    locked_balance_busd = balance_busd[:locked].to_f

    p "Free BNB: #{free_balance_bnb}"
    p "Free BUSD: #{free_balance_busd}"
    10.times do
      sleep INTERVAL_TIME_CALC_AVG
      last_price = client.ticker_24hr(symbol: SYMBOL)[:lastPrice].to_f
      prices.push last_price
    end

    orders = client.open_orders(symbol: SYMBOL)
    buy_orders = orders.select { |o| o[:side] == 'BUY' }
    sell_orders = orders.select { |o| o[:side] == 'SELL' }

    avg_price = prices.sum / prices.size
    price = calc_price(avg_price, buy_orders, sell_orders)
    buy_price = price[:buy_price] > prices.last ? prices.last : price[:buy_price]
    buy_price = buy_price.round(1)
    sell_price = price[:sell_price] < prices.last ? prices.last : price[:sell_price]
    sell_price = sell_price.round(1)

    p "avg_price:#{avg_price}"
    p "buy_price:#{buy_price}"
    p "sell_price:#{sell_price}"

    if can_sell?(free_balance_bnb, sell_orders) && can_buy?(free_balance_busd, buy_orders)
      response_sell = client.new_order(symbol: SYMBOL, side: 'SELL', price: sell_price, quantity: QUANTITY_BNB,
                                       type: 'LIMIT', timeInForce: 'GTC')
      p response_sell
      slack.post "Sell: Price: #{response_sell[:price].to_f.round(1)}, Quantity: #{response_sell[:origQty].to_f.round(3)}"
      response_buy = client.new_order(symbol: SYMBOL, side: 'BUY', price: buy_price, quantity: QUANTITY_BNB,
                                      type: 'LIMIT', timeInForce: 'GTC')
      p response_buy
      slack.post "Buy: Price: #{response_buy[:price].to_f.round(1)}, Quantity: #{response_sell[:origQty].to_f.round(3)}"
      slack.post "Balance: BNB:#{free_balance_bnb.to_f + locked_balance_bnb.to_f}, BUSD:#{free_balance_busd.to_f + locked_balance_busd.to_f}"
    end
    p '===== END ====='
  rescue StandardError => e
    p e
    slack.post "<!channel>#{e}"
  end
  sleep INTERVAL_TIME_DO
end
