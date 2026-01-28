//+------------------------------------------------------------------+
//|                                         BespojiMagic_Radar.mq4   |
//|                      べすぽじの魔術 - セットアップ検知（Radar）      |
//|                         Copyright 2026, Expert MQL4 Developer    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Expert MQL4 Developer"
#property link      ""
#property version   "2.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 7

// インジケーターバッファ
double BuySignalBuffer[];      // Buffer 0: 買いシグナル（上向き矢印）
double SellSignalBuffer[];     // Buffer 1: 売りシグナル（下向き矢印）
double UpperBandBuffer[];      // Buffer 2: BB上限（+2σ）
double MiddleBandBuffer[];     // Buffer 3: BB中間（SMA）
double LowerBandBuffer[];      // Buffer 4: BB下限（-2σ）
double BreakUpStateBuffer[];   // Buffer 5: 買いセットアップ中（ブレイク済み）
double BreakDownStateBuffer[]; // Buffer 6: 売りセットアップ中（ブレイク済み）

//--- 入力パラメータ ---

// ボリンジャーバンド設定
input int    BB_Period = 21;                    // BB期間
input double BB_Deviation = 2.0;                // BB偏差
input int    BB_AppliedPrice = PRICE_CLOSE;     // 適用価格

// ブレイク検知設定
input int    Lookback_Period = 20;              // 高値・安値の判定期間
input int    Break_Validity = 10;               // ブレイク後の有効期限（足の本数）

// 1時間足MAフィルター設定
input bool   Enable_H1_Filter = false;          // H1 MAフィルター有効化
input int    H1_MA_Period = 21;                 // H1 MA期間

// TP/SLライン設定
input bool   Show_TP_SL_Lines = true;           // TP/SLライン表示
input double SL_Offset_Pips = 2.0;              // SL位置のオフセット（pips）
input color  TP_Line_Color = clrAqua;           // TPライン色
input color  SL_Line_Color = clrRed;            // SLライン色

// アラート設定
input bool   Enable_Sound_Alert = true;         // サウンドアラート
input bool   Enable_Mobile_Alert = false;       // モバイル通知

// 矢印表示設定
input color  Buy_Arrow_Color = clrLime;         // 買いシグナル矢印色
input color  Sell_Arrow_Color = clrRed;         // 売りシグナル矢印色
input int    Arrow_Size = 2;                    // 矢印サイズ

// ボリンジャーバンド表示設定
input color  BB_Upper_Color = clrDodgerBlue;    // BB上限線の色
input color  BB_Middle_Color = clrYellow;       // BB中間線の色
input color  BB_Lower_Color = clrDodgerBlue;    // BB下限線の色
input int    BB_Line_Width = 1;                 // BBライン幅

//--- グローバル変数（ブレイク状態管理）---
datetime last_break_up_time = 0;      // 最後の高値ブレイク時刻
datetime last_break_down_time = 0;    // 最後の安値ブレイク時刻

// アラート送信済み管理（重複防止）
datetime last_buy_alert_time = 0;
datetime last_sell_alert_time = 0;

// TP/SLラインの名前（管理用）
string buy_tp_line_name = "BespojiMagic_BuyTP";
string buy_sl_line_name = "BespojiMagic_BuySL";
string sell_tp_line_name = "BespojiMagic_SellTP";
string sell_sl_line_name = "BespojiMagic_SellSL";

//+------------------------------------------------------------------+
//| カスタムインジケーター初期化関数                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // バッファの割り当て
   SetIndexBuffer(0, BuySignalBuffer);
   SetIndexBuffer(1, SellSignalBuffer);
   SetIndexBuffer(2, UpperBandBuffer);
   SetIndexBuffer(3, MiddleBandBuffer);
   SetIndexBuffer(4, LowerBandBuffer);
   SetIndexBuffer(5, BreakUpStateBuffer);
   SetIndexBuffer(6, BreakDownStateBuffer);
   
   // 買いシグナル矢印の設定
   SetIndexStyle(0, DRAW_ARROW, EMPTY, Arrow_Size, Buy_Arrow_Color);
   SetIndexArrow(0, 233);  // 上向き矢印
   SetIndexLabel(0, "Buy Signal");
   
   // 売りシグナル矢印の設定
   SetIndexStyle(1, DRAW_ARROW, EMPTY, Arrow_Size, Sell_Arrow_Color);
   SetIndexArrow(1, 234);  // 下向き矢印
   SetIndexLabel(1, "Sell Signal");
   
   // ボリンジャーバンドの描画設定
   SetIndexStyle(2, DRAW_LINE, EMPTY, BB_Line_Width, BB_Upper_Color);
   SetIndexLabel(2, "BB Upper (+2sigma)");
   
   SetIndexStyle(3, DRAW_LINE, EMPTY, BB_Line_Width, BB_Middle_Color);
   SetIndexLabel(3, "BB Middle (SMA)");
   
   SetIndexStyle(4, DRAW_LINE, EMPTY, BB_Line_Width, BB_Lower_Color);
   SetIndexLabel(4, "BB Lower (-2sigma)");
   
   SetIndexStyle(5, DRAW_NONE);
   SetIndexLabel(5, "Buy Setup State");
   
   SetIndexStyle(6, DRAW_NONE);
   SetIndexLabel(6, "Sell Setup State");
   
   // インジケーター名の設定
   // Set indicator short name
   IndicatorShortName("Bespoji Magic Radar(BB:" + IntegerToString(BB_Period) + 
                      ", LB:" + IntegerToString(Lookback_Period) + ")");
   
   // Timeframe check (5-minute recommended)
   if(Period() != PERIOD_M5)
   {
      Alert("Warning: This indicator is recommended for 5-minute charts (M5).");
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| カスタムインジケーター終了関数                                      |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // TP/SLラインを削除
   DeleteTPSLLines();
}

//+------------------------------------------------------------------+
//| カスタムインジケーター計算関数                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   // 必要なバー数の確認
   if(rates_total < BB_Period + Lookback_Period)
      return(0);
   
   int start;
   
   // 初回計算または全体再計算
   if(prev_calculated == 0)
   {
      start = rates_total - 1;
      // バッファの初期化
      ArrayInitialize(BuySignalBuffer, EMPTY_VALUE);
      ArrayInitialize(SellSignalBuffer, EMPTY_VALUE);
      ArrayInitialize(BreakUpStateBuffer, 0.0);
      ArrayInitialize(BreakDownStateBuffer, 0.0);
   }
   else
   {
      start = rates_total - prev_calculated;
      // 新しいバーのみ処理（最新の数本を再計算）
      if(start < 3) start = 3;
   }
   
   // 各バーに対してロジックを実行
   for(int i = start; i >= 1; i--)
   {
      // ボリンジャーバンドの計算
      CalculateBollingerBands(i);
      
      // シグナルバッファの初期化
      BuySignalBuffer[i] = EMPTY_VALUE;
      SellSignalBuffer[i] = EMPTY_VALUE;
      BreakUpStateBuffer[i] = 0.0;
      BreakDownStateBuffer[i] = 0.0;
      
      // ブレイク状態の出力（Trigger用）
   if(last_break_up_time != 0)
   {
      // 有効期限切れチェック
      int break_bar = iBarShift(NULL, 0, last_break_up_time, false);
      if(break_bar >= 0 && (break_bar - i) <= Break_Validity)
      {
         BreakUpStateBuffer[i] = 1.0;
      }
   }
   
   if(last_break_down_time != 0)
   {
      // 有効期限切れチェック
      int break_bar = iBarShift(NULL, 0, last_break_down_time, false);
      if(break_bar >= 0 && (break_bar - i) <= Break_Validity)
      {
         BreakDownStateBuffer[i] = 1.0;
      }
   }
   
   // 高値ブレイクの検知
      DetectHighBreak(i, high);
      
      // 安値ブレイクの検知
      DetectLowBreak(i, low);
      
      // 買いシグナルの生成
      GenerateBuySignal(i, open, high, low, close);
      
      // 売りシグナルの生成
      GenerateSellSignal(i, open, high, low, close);
   }
   
   // リアルタイムアラート（最新の確定足のみ）
   if(prev_calculated > 0 && rates_total > prev_calculated)
   {
      CheckAndSendAlerts(1, time);
   }
   
   return(rates_total);
}

//+------------------------------------------------------------------+
//| ボリンジャーバンドの計算                                           |
//+------------------------------------------------------------------+
void CalculateBollingerBands(int shift)
{
   // iMAを使用してSMAを計算
   double sma = iMA(NULL, 0, BB_Period, 0, MODE_SMA, BB_AppliedPrice, shift);
   
   // 標準偏差の計算
   double sum = 0.0;
   for(int j = 0; j < BB_Period; j++)
   {
      double price;
      switch(BB_AppliedPrice)
      {
         case PRICE_CLOSE:  price = iClose(NULL, 0, shift + j); break;
         case PRICE_OPEN:   price = iOpen(NULL, 0, shift + j); break;
         case PRICE_HIGH:   price = iHigh(NULL, 0, shift + j); break;
         case PRICE_LOW:    price = iLow(NULL, 0, shift + j); break;
         case PRICE_MEDIAN: price = (iHigh(NULL, 0, shift + j) + iLow(NULL, 0, shift + j)) / 2.0; break;
         case PRICE_TYPICAL: price = (iHigh(NULL, 0, shift + j) + iLow(NULL, 0, shift + j) + iClose(NULL, 0, shift + j)) / 3.0; break;
         case PRICE_WEIGHTED: price = (iHigh(NULL, 0, shift + j) + iLow(NULL, 0, shift + j) + 2 * iClose(NULL, 0, shift + j)) / 4.0; break;
         default: price = iClose(NULL, 0, shift + j); break;
      }
      sum += MathPow(price - sma, 2);
   }
   
   double stddev = MathSqrt(sum / BB_Period);
   
   // バッファに値を設定
   MiddleBandBuffer[shift] = sma;
   UpperBandBuffer[shift] = sma + (BB_Deviation * stddev);
   LowerBandBuffer[shift] = sma - (BB_Deviation * stddev);
}

//+------------------------------------------------------------------+
//| 高値ブレイクの検知                                                |
//+------------------------------------------------------------------+
void DetectHighBreak(int shift, const double &high[])
{
   // 最低限のデータが必要
   if(shift + Lookback_Period + 1 >= Bars)
      return;
   
   // 過去N本の最高値を取得（現在のバーとひとつ前のバーは除外）
   double highest = iHigh(NULL, 0, iHighest(NULL, 0, MODE_HIGH, Lookback_Period, shift + 2));
   
   // 前のバーが高値をブレイクしたか確認
   if(high[shift] > highest)
   {
      // ブレイク情報を記録（時刻のみ）
      last_break_up_time = iTime(NULL, 0, shift);
   }
}

//+------------------------------------------------------------------+
//| 安値ブレイクの検知                                                |
//+------------------------------------------------------------------+
void DetectLowBreak(int shift, const double &low[])
{
   // 最低限のデータが必要
   if(shift + Lookback_Period + 1 >= Bars)
      return;
   
   // 過去N本の最安値を取得（現在のバーとひとつ前のバーは除外）
   double lowest = iLow(NULL, 0, iLowest(NULL, 0, MODE_LOW, Lookback_Period, shift + 2));
   
   // 前のバーが安値をブレイクしたか確認
   if(low[shift] < lowest)
   {
      // ブレイク情報を記録（時刻のみ）
      last_break_down_time = iTime(NULL, 0, shift);
   }
}

//+------------------------------------------------------------------+
//| 買いシグナルの生成                                                |
//+------------------------------------------------------------------+
void GenerateBuySignal(int shift, const double &open[], const double &high[], 
                       const double &low[], const double &close[])
{
   // 有効期限内に高値ブレイクが発生しているか確認
   if(last_break_up_time == 0)
      return;
   
   // ブレイク発生時刻から現在の足までの距離を計算
   int break_bar = iBarShift(NULL, 0, last_break_up_time, false);
   if(break_bar < 0 || (break_bar - shift) > Break_Validity)
      return;
   
   // BB-2σにタッチしているか確認（安値がBB下限以下）
   if(low[shift] > LowerBandBuffer[shift])
      return;
   
   // 陽線（終値 > 始値）であることを確認
   if(close[shift] <= open[shift])
      return;
   
   // 1時間足MAフィルター（有効時のみ）
   if(Enable_H1_Filter)
   {
      // 1時間足の21SMAを取得
      double h1_ma = iMA(NULL, PERIOD_H1, H1_MA_Period, 0, MODE_SMA, PRICE_CLOSE, 0);
      // 買いサインは価格がH1 MAより上の場合のみ
      if(close[shift] <= h1_ma)
         return;
   }
   
   // 矢印の表示位置を計算（5桁業者対応：30ポイント = 3pips）
   double arrow_offset = 30 * Point;
   // 4桁業者の場合は自動調整（Digitsで判定）
   if(Digits == 3 || Digits == 5)
      arrow_offset = 30 * Point;  // 5桁業者：30ポイント = 3pips
   else
      arrow_offset = 3 * Point;   // 4桁業者：3ポイント = 3pips
   
   // 全ての条件を満たした場合、買いシグナルを表示
   BuySignalBuffer[shift] = low[shift] - arrow_offset;
   
   // ブレイク状態をリセット（同じブレイクで複数シグナルを出さない）
   last_break_up_time = 0;
   
   // TP/SLラインを描画
   if(Show_TP_SL_Lines && shift == 1)  // 最新の確定足のみ
   {
      DrawBuyTPSLLines(shift, low, close);
   }
}

//+------------------------------------------------------------------+
//| 売りシグナルの生成                                                |
//+------------------------------------------------------------------+
void GenerateSellSignal(int shift, const double &open[], const double &high[], 
                        const double &low[], const double &close[])
{
   // 有効期限内に安値ブレイクが発生しているか確認
   if(last_break_down_time == 0)
      return;
   
   // ブレイク発生時刻から現在の足までの距離を計算
   int break_bar = iBarShift(NULL, 0, last_break_down_time, false);
   if(break_bar < 0 || (break_bar - shift) > Break_Validity)
      return;
   
   // BB+2σにタッチしているか確認（高値がBB上限以上）
   if(high[shift] < UpperBandBuffer[shift])
      return;
   
   // 陰線（終値 < 始値）であることを確認
   if(close[shift] >= open[shift])
      return;
   
   // 1時間足MAフィルター（有効時のみ）
   if(Enable_H1_Filter)
   {
      // 1時間足の21SMAを取得
      double h1_ma = iMA(NULL, PERIOD_H1, H1_MA_Period, 0, MODE_SMA, PRICE_CLOSE, 0);
      // 売りサインは価格がH1 MAより下の場合のみ
      if(close[shift] >= h1_ma)
         return;
   }
   
   // 矢印の表示位置を計算（5桁業者対応：30ポイント = 3pips）
   double arrow_offset = 30 * Point;
   // 4桁業者の場合は自動調整（Digitsで判定）
   if(Digits == 3 || Digits == 5)
      arrow_offset = 30 * Point;  // 5桁業者：30ポイント = 3pips
   else
      arrow_offset = 3 * Point;   // 4桁業者：3ポイント = 3pips
   
   // 全ての条件を満たした場合、売りシグナルを表示
   SellSignalBuffer[shift] = high[shift] + arrow_offset;
   
   // ブレイク状態をリセット（同じブレイクで複数シグナルを出さない）
   last_break_down_time = 0;
   
   // TP/SLラインを描画
   if(Show_TP_SL_Lines && shift == 1)  // 最新の確定足のみ
   {
      DrawSellTPSLLines(shift, high, close);
   }
}

//+------------------------------------------------------------------+
//| アラートのチェックと送信                                           |
//+------------------------------------------------------------------+
void CheckAndSendAlerts(int shift, const datetime &time[])
{
   // 買いシグナルのアラート
   if(BuySignalBuffer[shift] != EMPTY_VALUE && last_buy_alert_time != time[shift])
   {
      SendSignalAlert("Buy Signal", shift, time);
      last_buy_alert_time = time[shift];
   }
   
   // 売りシグナルのアラート
   if(SellSignalBuffer[shift] != EMPTY_VALUE && last_sell_alert_time != time[shift])
   {
      SendSignalAlert("Sell Signal", shift, time);
      last_sell_alert_time = time[shift];
   }
}

//+------------------------------------------------------------------+
//| シグナルアラートの送信                                             |
//+------------------------------------------------------------------+
void SendSignalAlert(string signal_type, int bar, const datetime &time[])
{
   string message = "Bespoji Magic: " + signal_type + " Triggered! | " + 
                    Symbol() + " | " +
                    TimeToString(time[bar], TIME_DATE|TIME_MINUTES);
   
   // サウンドアラート（画面にも表示）
   if(Enable_Sound_Alert)
   {
      Alert(message);
   }
   
   // ログに記録
   Print(message);
   
   // モバイル通知
   if(Enable_Mobile_Alert)
   {
      SendNotification(message);
   }
}

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 買いサイン用TP/SLライン描画                                       |
//+------------------------------------------------------------------+
void DrawBuyTPSLLines(int shift, const double &low[], const double &close[])
{
   // 古いラインを削除
   DeleteTPSLLines();
   
   // pips計算用の乗数（4桁or5桁業者対応）
   double pip_multiplier = (Digits == 3 || Digits == 5) ? 10.0 : 1.0;
   double sl_offset = SL_Offset_Pips * Point * pip_multiplier;
   
   // SL: Lookback_Period内の最安値 - SL_Offset
   double lowest = iLow(NULL, 0, iLowest(NULL, 0, MODE_LOW, Lookback_Period, shift + 1));
   double sl_price = lowest - sl_offset;
   
   // TP: サイン確定時のBB+2σ
   double tp_price = UpperBandBuffer[shift];
   
   // SLライン描画
   ObjectCreate(0, buy_sl_line_name, OBJ_HLINE, 0, 0, sl_price);
   ObjectSetInteger(0, buy_sl_line_name, OBJPROP_COLOR, SL_Line_Color);
   ObjectSetInteger(0, buy_sl_line_name, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, buy_sl_line_name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, buy_sl_line_name, OBJPROP_BACK, true);
   ObjectSetString(0, buy_sl_line_name, OBJPROP_TEXT, "Buy SL: " + DoubleToString(sl_price, Digits));
   
   // TPライン描画
   ObjectCreate(0, buy_tp_line_name, OBJ_HLINE, 0, 0, tp_price);
   ObjectSetInteger(0, buy_tp_line_name, OBJPROP_COLOR, TP_Line_Color);
   ObjectSetInteger(0, buy_tp_line_name, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, buy_tp_line_name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, buy_tp_line_name, OBJPROP_BACK, true);
   ObjectSetString(0, buy_tp_line_name, OBJPROP_TEXT, "Buy TP: " + DoubleToString(tp_price, Digits));
}

//+------------------------------------------------------------------+
//| 売りサイン用TP/SLライン描画                                       |
//+------------------------------------------------------------------+
void DrawSellTPSLLines(int shift, const double &high[], const double &close[])
{
   // 古いラインを削除
   DeleteTPSLLines();
   
   // pips計算用の乗数（4桁or5桁業者対応）
   double pip_multiplier = (Digits == 3 || Digits == 5) ? 10.0 : 1.0;
   double sl_offset = SL_Offset_Pips * Point * pip_multiplier;
   
   // SL: Lookback_Period内の最高値 + SL_Offset
   double highest = iHigh(NULL, 0, iHighest(NULL, 0, MODE_HIGH, Lookback_Period, shift + 1));
   double sl_price = highest + sl_offset;
   
   // TP: サイン確定時のBB-2σ
   double tp_price = LowerBandBuffer[shift];
   
   // SLライン描画
   ObjectCreate(0, sell_sl_line_name, OBJ_HLINE, 0, 0, sl_price);
   ObjectSetInteger(0, sell_sl_line_name, OBJPROP_COLOR, SL_Line_Color);
   ObjectSetInteger(0, sell_sl_line_name, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, sell_sl_line_name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, sell_sl_line_name, OBJPROP_BACK, true);
   ObjectSetString(0, sell_sl_line_name, OBJPROP_TEXT, "Sell SL: " + DoubleToString(sl_price, Digits));
   
   // TPライン描画
   ObjectCreate(0, sell_tp_line_name, OBJ_HLINE, 0, 0, tp_price);
   ObjectSetInteger(0, sell_tp_line_name, OBJPROP_COLOR, TP_Line_Color);
   ObjectSetInteger(0, sell_tp_line_name, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, sell_tp_line_name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, sell_tp_line_name, OBJPROP_BACK, true);
   ObjectSetString(0, sell_tp_line_name, OBJPROP_TEXT, "Sell TP: " + DoubleToString(tp_price, Digits));
}

//+------------------------------------------------------------------+
//| TP/SLラインを削除                                                |
//+------------------------------------------------------------------+
void DeleteTPSLLines()
{
   // 既存のTP/SLラインを削除
   if(ObjectFind(0, buy_tp_line_name) >= 0)
      ObjectDelete(0, buy_tp_line_name);
   
   if(ObjectFind(0, buy_sl_line_name) >= 0)
      ObjectDelete(0, buy_sl_line_name);
   
   if(ObjectFind(0, sell_tp_line_name) >= 0)
      ObjectDelete(0, sell_tp_line_name);
   
   if(ObjectFind(0, sell_sl_line_name) >= 0)
      ObjectDelete(0, sell_sl_line_name);
}

//+------------------------------------------------------------------+
