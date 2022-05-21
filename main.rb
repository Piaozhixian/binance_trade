require 'binance'
require 'dotenv'
require 'slack/incoming/webhooks'

Dotenv.load

SYMBOL = 'BNBBUSD'
QUANTITY_BNB = 0.025
QUANTITY_BUSD = 12
SHORT_CANDLE_NUM = 7
LONG_CANDLE_NUM = 30
KLINE_INTERVAL = '5m'

client = Binance::Spot.new(key: ENV['KEY'], secret: ENV['SECRET'])
slack = Slack::Incoming::Webhooks.new ENV['WEBHOOK_URL']

# 最新の価額でMAを計算
def calc_ma(candles, candle_num)
  closes = []
  last_candles = candles.last(candle_num)
  last_candles.each do |candle|
    closes.push(candle[4].to_f)
  end
  closes.sum / closes.size
end

# 一個前のcandleまでの価額でMAを計算
def calc_ma_before(candles, candle_num)
  closes = []
  last_candles = candles.last(candle_num + 1)

  last_candles.pop
  last_candles.each do |candle|
    closes.push(candle[4].to_f)
  end
  closes.sum / closes.size
end

def check_cross(ma5, ma15, ma5_before, ma15_before)
  if ma5_before < ma15_before && ma5 > ma15
    'golden'
  elsif ma5_before > ma15_before && ma5 < ma15
    'dead'
  end
end

def can_sell?(free_balance_bnb)
  free_balance_bnb > QUANTITY_BNB
end

def can_buy?(free_balance_busd)
  free_balance_busd > QUANTITY_BUSD
end

loop do
  sleep 5
  begin
    candles = client.klines(symbol: SYMBOL, interval: KLINE_INTERVAL, startTime: (Time.now.to_i - 3600 * 24) * 1000)
    ma5 = calc_ma(candles, SHORT_CANDLE_NUM)
    ma15 = calc_ma(candles, LONG_CANDLE_NUM)
    ma5_before = calc_ma_before(candles, SHORT_CANDLE_NUM)
    ma15_before = calc_ma_before(candles, LONG_CANDLE_NUM)

    p "MA5:#{ma5.round(3)}, MA15:#{ma15.round(3)}"
    cross_flag = check_cross(ma5, ma15, ma5_before, ma15_before)

    if cross_flag == 'golden'
      p 'golden'
      balance_busd = client.account[:balances].select { |bal| bal[:asset] == 'BUSD' }.first
      free_balance_busd = balance_busd[:free].to_f
      if free_balance_busd > 12
        last_price = client.ticker_24hr(symbol: SYMBOL)[:lastPrice].to_f
        p "last_price:#{last_price},free_balance_busd:#{free_balance_busd} "
        quantity = (free_balance_busd / last_price).to_f.floor(3)
        price = last_price.to_f.round(1)
        response = client.new_order(symbol: SYMBOL, side: 'BUY', price: price, quantity: quantity,
                                    type: 'LIMIT', timeInForce: 'GTC')
        p response
        slack.post "[Buy] price: #{price}, quantity: #{quantity}"
      end
    elsif cross_flag == 'dead'
      p 'dead'

      balance_bnb = client.account[:balances].select { |bal| bal[:asset] == 'BNB' }.first
      free_balance_bnb = balance_bnb[:free].to_f.floor(3)
      if free_balance_bnb > 0.025
        last_price = client.ticker_24hr(symbol: SYMBOL)[:lastPrice].to_f
        price = last_price.to_f.floor(1)
        response = client.new_order(symbol: SYMBOL, side: 'SELL', price: price, quantity: free_balance_bnb,
                                    type: 'LIMIT', timeInForce: 'GTC')

        p response
        slack.post "[Sell] price: #{price}, quantity: #{free_balance_bnb}"
      end
    end
  rescue StandardError => e
    slack.post e.to_s
  end
end
