require 'binance'
require 'dotenv'
require 'slack/incoming/webhooks'

Dotenv.load

INTERVAL_TIME_CALC_AVG = 5
INTERVAL_TIME_DO = 10

QUANTITY_GMT = 14
QUANTITY_BUSD = 12
SYMBOL = 'GMTBUSD'
SELL_ORDER_MAX = 50
BUY_ORDER_MAX = 50
KLINE_INTERVAL = '5m'

client = Binance::Spot.new(key: ENV['KEY'], secret: ENV['SECRET'])
slack = Slack::Incoming::Webhooks.new ENV['WEBHOOK_URL']
slack_dev_log = Slack::Incoming::Webhooks.new ENV['LOG_WEBHOOK_URL']

def can_sell?(free_balance_gmt, sell_orders)
  return false if sell_orders.count >= SELL_ORDER_MAX

  free_balance_gmt > QUANTITY_BNB
end

def can_buy?(free_balance_busd, buy_orders)
  return false if buy_orders.count >= BUY_ORDER_MAX

  free_balance_busd > QUANTITY_BUSD
end

# kline response
# [
#   [
#     1499040000000,      // 开盘时间
#     "0.01634790",       // 开盘价
#     "0.80000000",       // 最高价
#     "0.01575800",       // 最低价
#     "0.01577100",       // 收盘价(当前K线未结束的即为最新价)
#     "148976.11427815",  // 成交量
#     1499644799999,      // 收盘时间
#     "2434.19055334",    // 成交额
#     308,                // 成交笔数
#     "1756.87402397",    // 主动买入成交量
#     "28.46694368",      // 主动买入成交额
#     "17928899.62484339" // 请忽略该参数
#   ]
# ]
# 10分間の下り幅をチェック、最初の10分間暴落し、最後の５分上がったらbottomとする
def check_is_bottom?(candles)
  candles = candles.last(3)

  # 一個前のcandleで3%以上暴落、且つ最新のcandleで0.2%以上の値上がりがあったらreturn true
  before_candle_start_price = candles[1][1].to_f
  last_candle_start_price = candles.last[1].to_f
  rate = last_candle_start_price / before_candle_start_price
  if rate < 0.97
    last_price = candles.last[4].to_f
    tmp_rate = last_price / last_candle_start_price
    return true if tmp_rate > 1.005
  end

  # 10分間の下り幅をチェック、最初の10分間暴落し、最後の５分上がったか
  return false if went_up?(candles[0])
  return false if went_up?(candles[1])
  return false unless went_up?(candles[2])

  start_price = candles[0][1].to_f
  bottom_price = candles[1][4].to_f

  diff_price = start_price - bottom_price
  diff_percent = (diff_price / start_price) * 100

  if diff_percent > 2
    slack_dev_log.post 'buttom'
    slack_dev_log.post "StartPrice: #{start_price}, BottomPrice: #{bottom_price}, DiffPercent: #{diff_percent}"
    return true
  end
  false
end

def went_up?(candle)
  start_price = candle[1].to_f
  end_price = candle[4].to_f

  start_price < end_price
end

def check_is_top?(candles)
  candles = candles.last(2)

  return false unless went_up?(candles[0])

  # 上一个candle的收盘价
  prev_last_price = candles[0][4].to_f
  # 现在的价格
  last_price = candles[1][4].to_f
  slack_dev_log = Slack::Incoming::Webhooks.new ENV['LOG_WEBHOOK_URL']

  p prev_last_price
  p last_price
  rate = last_price / prev_last_price
  p rate
  slack_dev_log.post "上一个收盘价：#{prev_last_price}\n现在的价格：#{last_price}, rate: #{rate}"

  return true if rate < 0.995

  false
end

# 持っている資産の8割
def calc_quantity(coin_name)
  client = Binance::Spot.new(key: ENV['KEY'], secret: ENV['SECRET'])
  balance_busd = client.account[:balances].select { |bal| bal[:asset] == coin_name }.first
  free_balance_busd = balance_busd[:free].to_f
  (free_balance_busd * 0.8).to_i
end

def calc_total(_gmt_price)
  client = Binance::Spot.new(key: ENV['KEY'], secret: ENV['SECRET'])
  balance_busd = client.account[:balances].select { |bal| bal[:asset] == 'BUSD' }.first
  balance_gmt = client.account[:balances].select { |bal| bal[:asset] == 'GMT' }.first
  p '==========================='
  p "BUSD: #{balance_busd[:free]}"
  p "GMT : #{balance_gmt[:free]} "
  p '---------------------------'
  p "total: #{balance_busd[:free]}"
  p '==========================='
end

while true
  begin
    candles = client.klines(symbol: SYMBOL, interval: KLINE_INTERVAL, startTime: (Time.now.to_i - 60 * 60) * 1000)

    if check_is_bottom?(candles)
      slack_dev_log.post 'bottom'
      file_string = File.read('trade_log.txt')
      string_arr = file_string.split(/\r\n|\r|\n/)

      last_traded_at = Time.parse(string_arr[0])
      last_order_type = string_arr[1].include?('BUY') ? 'BUY' : 'SELL'
      if ((Time.now - last_traded_at) > 5 * 60) && last_order_type == 'SELL'
        # buy gmt
        response = client.new_order(symbol: SYMBOL, side: 'BUY', quantity: calc_quantity('BUSD'),
                                    type: 'MARKET')
        file = File.open('trade_log.txt', 'w')
        file.puts Time.now
        file.puts response
        file.close
        slack.post "[BUY] #{response[:fills]}"

      end
    end

    if check_is_top?(candles)
      slack_dev_log.post 'top'
      file_string = File.read('trade_log.txt')
      string_arr = file_string.split(/\r\n|\r|\n/)

      last_traded_at = Time.parse(string_arr[0])
      last_order_type = string_arr[1].include?('BUY') ? 'BUY' : 'SELL'
      if ((Time.now - last_traded_at) > 5 * 60) && last_order_type == 'BUY'
        # sell gmt
        response = client.new_order(symbol: SYMBOL, side: 'SELL', quantity: calc_quantity('GMT'),
                                    type: 'MARKET')

        file = File.open('trade_log.txt', 'w')
        file.puts Time.now
        file.puts response
        file.close
        slack.post "[SELL] #{response[:fills]}"

      end
    end

    calc_total(candles.last[4])
  rescue StandardError => e
    p e
    slack.post "<!channel>#{e}"
  end
  sleep INTERVAL_TIME_DO
end
