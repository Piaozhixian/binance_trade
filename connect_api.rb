require 'binance'
require 'dotenv'

Dotenv.load

INTERVAL_TIME = 5
QUANTITY = 0.025
SYMBOL = 'BNBBUSD'
SELL_ORDER_MAX = 3
BUY_ORDER_MAX = 3
client = Binance::Spot.new(key: ENV['KEY'], secret: ENV['SECRET'])

def can_sell?(free_balance_bnb, sell_orders)
    return false if sell_orders.count >= SELL_ORDER_MAX
    free_balance_bnb > QUANTITY ? true : false
end

def can_buy?(free_balance_busd, buy_orders)
    return false if buy_orders.count >= BUY_ORDER_MAX
    free_balance_busd > QUANTITY ? true : false
end

while true
    sleep 60

    p "===== START ====="
    cnt = 0
    prices = []

    balance_bnb = client.account[:balances].select{ |bal| bal[:asset] == "BNB"}.first
    free_balance_bnb = balance_bnb[:free].to_f
    balance_busd = client.account[:balances].select{ |bal| bal[:asset] == "BUSD"}.first
    free_balance_busd = balance_busd[:free].to_f

    p "Free BNB: #{free_balance_bnb}"
    p "Free BUSD: #{free_balance_busd}"
    10.times do
        sleep INTERVAL_TIME
        last_price = client.ticker_24hr(symbol: SYMBOL)[:lastPrice].to_f
        prices.push last_price
    end
    avg_price = prices.sum/(prices.size)
    buy_price = (avg_price * 0.9995).round(1)
    sell_price = (avg_price * 1.0007).round(1)

    p "avg_price:#{avg_price}"
    p "buy_price:#{buy_price}"
    p "sell_price:#{sell_price}"

    orders = client.open_orders(symbol: SYMBOL)
    buy_orders = orders.select{|o| o[:side] == "BUY"}
    sell_orders = orders.select{|o| o[:side] == "SELL"}

    if can_sell?(free_balance_bnb, sell_orders) && can_buy?(free_balance_busd, buy_orders)
        response_sell = client.new_order(symbol: SYMBOL, side: 'SELL', price: sell_price, quantity: QUANTITY, type: 'LIMIT', timeInForce: 'GTC')
        p response_sell
        response_buy = client.new_order(symbol: SYMBOL, side: 'BUY', price: buy_price, quantity: QUANTITY, type: 'LIMIT', timeInForce: 'GTC')
        p response_buy
    end
    p "===== END ====="
end


