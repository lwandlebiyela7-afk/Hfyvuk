# XAUUSD TrendBot (MT5 Expert Advisor)

A starter MQL5 Expert Advisor for demo testing. It uses an EMA 50/EMA 200 trend filter, a pullback condition, ATR-based stop-loss, a 2R take-profit, position sizing based on a configurable equity risk percentage, a spread filter, and a daily-loss entry guard.

## Important limitation
This repository stores source code; GitHub does not run an MT5 Expert Advisor. MetaTrader 5 desktop terminal on Windows must be running and connected to the broker for the EA to trade. The Android MT5 app cannot run EAs directly. If you only have Android, you can edit/store the code on GitHub, but you need access to a Windows computer or a Windows VPS to compile and run it.

## Demo-only setup
1. Open the repository on GitHub and create `XAUUSD_TrendBot.mq5` in the root, then paste the EA source.
2. On Windows, open MT5 and choose **File → Open Data Folder**.
3. Open `MQL5/Experts/`, place `XAUUSD_TrendBot.mq5` there, and open it in MetaEditor.
4. Compile with F7. Fix any compiler errors before proceeding.
5. In MT5, open the broker's exact Gold symbol chart (the name can include a suffix such as `XAUUSD.a`), set the chart to M15, and attach the EA.
6. Enable Algo Trading and the EA's automated-trading permission. Keep it on a DEMO account.
7. Backtest using Strategy Tester with realistic spreads and commission, then run it on demo and inspect the Experts/Journal logs.

## Starter settings
- Signal timeframe: M15
- EMA trend filter: 50 / 200
- ATR period: 14
- Risk per trade: 0.5% of equity
- Stop: 1.5 × ATR
- Take profit: 2 × initial stop distance
- Daily loss guard: stop opening new trades after 2% equity loss from the day's starting equity
- One position for this EA per symbol at a time

## Limitations / risks
- No strategy guarantees profit. This starter strategy is not validated and can lose money.
- The daily guard prevents new entries; it does not force-close open positions or include losses from other EAs in a separate risk budget.
- Stops can slip during fast markets. Broker contract specifications, tick values, volume steps, and stop-distance rules differ.
- The EA does not trail stops, trade news, or use machine learning.
- The daily guard resets based on the broker server's calendar day.
- Test symbol suffixes, tick values, lot sizing, spread thresholds, and order execution on demo before considering any live use.
