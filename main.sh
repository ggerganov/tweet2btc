#!/bin/bash

wd=$(dirname $0)
cd $wd
wd=$(pwd)

bot_id="tweet2btc"

source .env

[ ! -f data/count ] && echo "Missing data/count" && exit 1
[ ! -f data/last-cmc ] && echo "Missing data/last-cmc" && exit 1
[ ! -f data/last-post ] && echo "Missing data/last-post" && exit 1
[ ! -f data/streak-best ] && echo "Missing data/streak-best" && exit 1
[ ! -f data/streak-curr ] && echo "Missing data/streak-curr" && exit 1

icon_up="⬆️"
icon_down="⬇️"
icon_correct="✅"
icon_wrong="❌"

LC_NUMERIC="en_US.UTF-8"

last_btc_price=$(cat data/last-cmc | jq -r ".data.BTC.quote.USD.price")
last_btc_price=$(printf "%.2f" $last_btc_price)

last_btc_updated=$(cat data/last-cmc | jq -r ".data.BTC.quote.USD.last_updated")

echo "Last BTC price:  $last_btc_price"
echo "Last BTC update: $last_btc_updated"

echo "Querying coinmarketcap.com ..."

nretry=10
while true ; do
    curl -H "X-CMC_PRO_API_KEY: $CMC_KEY" -G https://pro-api.coinmarketcap.com/v1/cryptocurrency/quotes/latest?symbol=BTC > data/last-cmc

    if grep -q "Gateway Timeout" data/last-cmc ; then
        nretry=$((nretry-1))
        echo "Gateway Timeout. Retries left: $nretry"
        if [ $nretry -eq 0 ] ; then
            echo "Too many retries. Aborting"
            exit 1
        fi
        sleep 3
    else
        break
    fi
done

timestamp=$(cat data/last-cmc | jq -r ".status.timestamp")
cp -v data/last-cmc data/$timestamp

# price info

curr_btc_price=$(cat data/last-cmc | jq -r ".data.BTC.quote.USD.price")
curr_btc_price=$(printf "%.2f" $curr_btc_price)

curr_btc_chng=$(cat data/last-cmc | jq -r ".data.BTC.quote.USD.percent_change_24h")
curr_btc_chng=$(printf "%.3f" $curr_btc_chng)

is_up=$(echo "$curr_btc_chng >= 0.0" | bc -l)

text_price_chng_icon="$icon_down"
if [ "$is_up" -eq 1 ] ; then
    text_price_chng_icon="$icon_up"
fi
#text_price="$curr_btc_price USD (prev: $last_btc_price | chng: $curr_btc_chng% $text_price_chng_icon)"
text_price="$curr_btc_price USD (chng: $curr_btc_chng% $text_price_chng_icon)"

# voting prediction

last_post_id=$(cat data/last-post | jq -r ".data.id")
echo "Last post id = $last_post_id"

./get-tweet.sh $last_post_id > data/last-tweet

votes_up=$(cat data/last-tweet | jq -r ".includes.polls[0].options[0].votes")
votes_down=$(cat data/last-tweet | jq -r ".includes.polls[0].options[1].votes")
votes_total=$(($votes_up + $votes_down))

text_prediction="$icon_up $votes_up vs $votes_down $icon_down"

# voting result

votes_is_up=$(echo "$votes_up >= $votes_down" | bc -l)

is_correct=0
text_result="Wrong prediction $icon_wrong"
if [ "$votes_total" -eq 0 ] ; then
    text_result="Not enough votes $icon_wrong"
else
    if [ "$votes_up" -eq "$votes_down" ] ; then
        text_result="No consensus $icon_wrong"
    else
        [ "$votes_is_up" -eq 1 ] && [ "$is_up" -eq 1 ] && text_result="Correct prediction $icon_correct" && is_correct=1
        [ "$votes_is_up" -eq 0 ] && [ "$is_up" -eq 0 ] && text_result="Correct prediction $icon_correct" && is_correct=1
    fi
fi

# streak

read -r count < data/count
read -r streak_best < data/streak-best
read -r streak_curr < data/streak-curr

if [ "$is_correct" -eq 1 ] ; then
    streak_curr=$(($streak_curr + 1))
    if [ "$streak_curr" -gt "$streak_best" ] ; then
        streak_best="$streak_curr"
    fi
else
    streak_curr=0
fi

echo "$streak_best" > data/streak-best
echo "$streak_curr" > data/streak-curr

echo "{
\"text\": \"\
Results #$count:\n\
\n\
Votes: $text_prediction\n\
BTC price: $text_price\n\
\n\
$text_result\n\
Streak: $streak_curr days (best: $streak_best)\n\
\n\
Prediction #$(($count + 1)):\n\
How will the BTC price change during the next 24 hours?\",
\"poll\": {
  \"options\": [\"$icon_up Increase\", \"$icon_down Decrease\"],
  \"duration_minutes\": 480
  }
}
" > data/post.json

#echo $text
#exit

set -x

twurl -u $bot_id -X POST /2/tweets -A "Content-type: application/json" -d "$(cat data/post.json)" > data/last-post

count=$(($count + 1))

echo $count > data/count
