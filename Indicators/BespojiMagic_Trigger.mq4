//+------------------------------------------------------------------+
//|                                       BespojiMagic_Trigger.mq4   |
//|                    べすぽじの魔術 - 足確定タイミング執行（Trigger）  |
//|                         Copyright 2026, Expert MQL4 Developer    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Expert MQL4 Developer"
#property link      ""
#property version   "2.10"
#property strict
#property indicator_chart_window
#property indicator_buffers 2

// インジケーターバッファ
double BuySignalBuffer[];      // Buffer 0: 買いシグナル（上向き矢印）
double SellSignalBuffer[];     // Buffer 1: 売りシグナル（下向き矢印）

//--- 入力パラメータ ---

// Radar設定
input string Radar_Indicator_Name = "BespojiMagic_Radar";  // Radarインジケーター名

// 執行ロジック設定
input bool   Use_M1_Confirmation = true;      // M1ダブルボトム確認（M1チャート推奨）
input double Double_Pattern_Pips = 1.5;       // ダブルボトム/トップ許容誤差 (pips)

// Radarパラメータ（iCustomに渡す用）
input int    BB_Period = 21;
input double BB_Deviation = 2.0;
input int    BB_AppliedPrice = PRICE_CLOSE;
input int    Lookback_Period = 20;
input int    Break_Validity = 10;
input bool   Enable_H1_Filter = false;
input int    H1_MA_Period = 21;
input bool   Show_TP_SL_Lines = true;
input double SL_Offset_Pips = 2.0;
input color  TP_Line_Color = clrAqua;
input color  SL_Line_Color = clrRed;
input bool   Enable_Sound_Alert = true;
input bool   Enable_Mobile_Alert = false;
input color  Buy_Arrow_Color = clrLime;
input color  Sell_Arrow_Color = clrRed;
input int    Arrow_Size = 2;
input color  BB_Upper_Color = clrDodgerBlue;
input color  BB_Middle_Color = clrYellow;
input color  BB_Lower_Color = clrDodgerBlue;
input int    BB_Line_Width = 1;

// カウントダウンタイマー設定
input color  Timer_Color = clrWhite;           // タイマー通常色
input color  Timer_Warning_Color = clrRed;     // タイマー警告色（10秒以内）
input int    Timer_FontSize = 24;              // タイマー文字サイズ
input int    Timer_X_Distance = 200;           // タイマーX位置
input int    Timer_Y_Distance = 50;            // タイマーY位置

// 矢印表示設定
input color  Trigger_Buy_Arrow_Color = clrLime;   // 買いシグナル矢印色
input color  Trigger_Sell_Arrow_Color = clrRed;   // 売りシグナル矢印色
input int    Trigger_Arrow_Size = 3;              // 矢印サイズ

//--- グローバル変数 ---
string timer_obj_name = "BespojiTrigger_Timer";
string status_obj_name = "BespojiTrigger_Status";

// アラート送信済み管理
datetime last_buy_alert_time = 0;
datetime last_sell_alert_time = 0;

//+------------------------------------------------------------------+
//| カスタムインジケーター初期化関数                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // バッファの割り当て
   SetIndexBuffer(0, BuySignalBuffer);
   SetIndexBuffer(1, SellSignalBuffer);
   
   // 買いシグナル矢印の設定
   SetIndexStyle(0, DRAW_ARROW, EMPTY, Trigger_Arrow_Size, Trigger_Buy_Arrow_Color);
   SetIndexArrow(0, 233);  // 上向き矢印
   SetIndexLabel(0, "Trigger Buy Signal");
   
   // 売りシグナル矢印の設定
   SetIndexStyle(1, DRAW_ARROW, EMPTY, Trigger_Arrow_Size, Trigger_Sell_Arrow_Color);
   SetIndexArrow(1, 234);  // 下向き矢印
   SetIndexLabel(1, "Trigger Sell Signal");
   
   // インジケーター名の設定
   IndicatorShortName("Bespoji Magic Trigger v2.1");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| カスタムインジケーター終了関数                                      |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // タイマーとステータス表示を削除
   ObjectDelete(0, timer_obj_name);
   ObjectDelete(0, status_obj_name);
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
   // ------------------------------
   // 1. Radarの状態を取得 (M5)
   // ------------------------------
   // M1チャートで稼働している場合、M5のShift 0を見れば最新の状態が分かる。
   // Radar Buffer 5: Buy Setup State (Break Up Active)
   // Radar Buffer 6: Sell Setup State (Break Down Active)
   
   double radar_buy_setup = iCustom(NULL, PERIOD_M5, Radar_Indicator_Name,
                                    BB_Period, BB_Deviation, BB_AppliedPrice,
                                    Lookback_Period, Break_Validity,
                                    Enable_H1_Filter, H1_MA_Period,
                                    Show_TP_SL_Lines, SL_Offset_Pips, TP_Line_Color, SL_Line_Color,
                                    Enable_Sound_Alert, Enable_Mobile_Alert,
                                    Buy_Arrow_Color, Sell_Arrow_Color, Arrow_Size,
                                    BB_Upper_Color, BB_Middle_Color, BB_Lower_Color, BB_Line_Width,
                                    5, 0); // Setup StateはリアルタイムでShift 0監視

   double radar_sell_setup = iCustom(NULL, PERIOD_M5, Radar_Indicator_Name,
                                     BB_Period, BB_Deviation, BB_AppliedPrice,
                                     Lookback_Period, Break_Validity,
                                     Enable_H1_Filter, H1_MA_Period,
                                     Show_TP_SL_Lines, SL_Offset_Pips, TP_Line_Color, SL_Line_Color,
                                     Enable_Sound_Alert, Enable_Mobile_Alert,
                                     Buy_Arrow_Color, Sell_Arrow_Color, Arrow_Size,
                                     BB_Upper_Color, BB_Middle_Color, BB_Lower_Color, BB_Line_Width,
                                     6, 0); // Setup StateはリアルタイムでShift 0監視

   // 従来ロジック用（足確定シグナル）
   double radar_buy_signal_legacy = iCustom(NULL, PERIOD_M5, Radar_Indicator_Name,
                                     BB_Period, BB_Deviation, BB_AppliedPrice,
                                     Lookback_Period, Break_Validity,
                                     Enable_H1_Filter, H1_MA_Period,
                                     Show_TP_SL_Lines, SL_Offset_Pips, TP_Line_Color, SL_Line_Color,
                                     Enable_Sound_Alert, Enable_Mobile_Alert,
                                     Buy_Arrow_Color, Sell_Arrow_Color, Arrow_Size,
                                     BB_Upper_Color, BB_Middle_Color, BB_Lower_Color, BB_Line_Width,
                                     0, 1); // 確定足Shift 1

   double radar_sell_signal_legacy = iCustom(NULL, PERIOD_M5, Radar_Indicator_Name,
                                      BB_Period, BB_Deviation, BB_AppliedPrice,
                                      Lookback_Period, Break_Validity,
                                      Enable_H1_Filter, H1_MA_Period,
                                      Show_TP_SL_Lines, SL_Offset_Pips, TP_Line_Color, SL_Line_Color,
                                      Enable_Sound_Alert, Enable_Mobile_Alert,
                                      Buy_Arrow_Color, Sell_Arrow_Color, Arrow_Size,
                                      BB_Upper_Color, BB_Middle_Color, BB_Lower_Color, BB_Line_Width,
                                      1, 1); // 確定足Shift 1


   // バッファの初期化（再計算用）
   ArrayInitialize(BuySignalBuffer, EMPTY_VALUE);
   ArrayInitialize(SellSignalBuffer, EMPTY_VALUE);

   bool m1_pattern_detected = false;
   string status_msg = "";

   // ------------------------------
   // 2. M1 ダブルボトムロジック
   // ------------------------------
   if (Use_M1_Confirmation && Period() == PERIOD_M1)
   {
      // --- 買いロジック ---
      if (radar_buy_setup != 0 && radar_buy_setup != EMPTY_VALUE)
      {
         // M1の過去15本(current shift 1..15)の安値（1点目）を探す
         int lowest_shift = iLowest(NULL, PERIOD_M1, MODE_LOW, 15, 1);
         if (lowest_shift != -1)
         {
             double first_point_low = iLow(NULL, PERIOD_M1, lowest_shift);
             
             // 現在の状態表示
             status_msg = "M1 First Point Detected - Waiting for 2nd Rebound (Buy)";
             m1_pattern_detected = true;

             // M1足確定時(Shift 1)の判定
             // 条件1: Shift 1が「1点目」ではないこと（最低1本以上の間隔がある＝V字ではなくW字）
             // 条件2: Shift 1の安値か終値が、1点目から誤差範囲内 (Double_Pattern_Pips)
             // 条件3: Shift 1が陽線 (Close > Open)
             
             double pips_diff = Double_Pattern_Pips * Point * ((Digits==3||Digits==5)?10:1);
             
             if (rates_total > prev_calculated) // 新しい足ができた瞬間のみ執行判定
             {
                 bool is_bullish = (close[1] > open[1]);
                 double dist = MathAbs(close[1] - first_point_low);
                 
                 // 簡易ダブルボトム判定: 
                 // 今回の終値が底値付近にあり、かつ陽線確定
                 if (is_bullish && dist <= pips_diff)
                 {
                     BuySignalBuffer[1] = low[1] - (30 * Point);
                     if (last_buy_alert_time != time[1])
                     {
                         SendTriggerAlert("M1 Double Bottom Buy", time[1]);
                         last_buy_alert_time = time[1];
                     }
                 }
             }
         }
      }

      // --- 売りロジック ---
      if (radar_sell_setup != 0 && radar_sell_setup != EMPTY_VALUE)
      {
         // M1の過去15本の高値（1点目）を探す
         int highest_shift = iHighest(NULL, PERIOD_M1, MODE_HIGH, 15, 1);
         if (highest_shift != -1)
         {
             double first_point_high = iHigh(NULL, PERIOD_M1, highest_shift);
             
             // 現在の状態表示
             status_msg = "M1 First Point Detected - Waiting for 2nd Rebound (Sell)";
             m1_pattern_detected = true;

             double pips_diff = Double_Pattern_Pips * Point * ((Digits==3||Digits==5)?10:1);
             
             if (rates_total > prev_calculated) // 新しい足ができた瞬間
             {
                 bool is_bearish = (close[1] < open[1]);
                 double dist = MathAbs(close[1] - first_point_high);
                 
                 if (is_bearish && dist <= pips_diff)
                 {
                     SellSignalBuffer[1] = high[1] + (30 * Point);
                     if (last_sell_alert_time != time[1])
                     {
                         SendTriggerAlert("M1 Double Top Sell", time[1]);
                         last_sell_alert_time = time[1];
                     }
                 }
             }
         }
      }
   }
   else 
   {
      // --- 従来ロジック (M5確定足 or M1使用設定オフ) ---
      // M1設定がオフ、またはM1チャート以外の場合は、Radarの矢印バッファをそのまま採用
      if(rates_total > prev_calculated || prev_calculated == 0)
      {
         if(radar_buy_signal_legacy != EMPTY_VALUE && radar_buy_signal_legacy != 0)
         {
            BuySignalBuffer[1] = low[1] - (30 * Point);
            if(last_buy_alert_time != time[1])
            {
               SendTriggerAlert("Buy Signal (Legacy)", time[1]);
               last_buy_alert_time = time[1];
            }
         }
         
         if(radar_sell_signal_legacy != EMPTY_VALUE && radar_sell_signal_legacy != 0)
         {
            SellSignalBuffer[1] = high[1] + (30 * Point);
            if(last_sell_alert_time != time[1])
            {
               SendTriggerAlert("Sell Signal (Legacy)", time[1]);
               last_sell_alert_time = time[1];
            }
         }
      }
      status_msg = "Waiting for M5 Close Signal...";
   }
   
   // --- Status Display Logic (Enhanced 4-State System) ---
   status_msg = "[Standby] Waiting for Setup"; 
   color status_color = clrGray;

   // 1. Check if M5 setup (breakout) is active
   bool setup_active = (radar_buy_setup != 0 && radar_buy_setup != EMPTY_VALUE) || 
                       (radar_sell_setup != 0 && radar_sell_setup != EMPTY_VALUE);

   if (!setup_active) {
       status_msg = "[Standby] Waiting for M5 Break";
       status_color = clrGray;
   } else {
       // 2. Check M1 Double Bottom/Top progress
       if (Use_M1_Confirmation && Period() == PERIOD_M1) {
           int shift_range = 15;
           // Note: In real-time, we check past 15 bars from shift 1 (closed bars)
           int m1_low_shift = iLowest(NULL, PERIOD_M1, MODE_LOW, shift_range, 1);
           int m1_high_shift = iHighest(NULL, PERIOD_M1, MODE_HIGH, shift_range, 1);

           if (radar_buy_setup != 0 && radar_buy_setup != EMPTY_VALUE) {
               // Buy Setup Active
               if (m1_low_shift != -1) {
                   status_msg = "[Forming] M1 Buy Pattern (Waiting 2nd)";
                   status_color = clrOrange;
               } else {
                   status_msg = "[Watching] M5 Sell Break. Waiting M1 1st Point";
                   status_color = clrGold;
               }
           } else if (radar_sell_setup != 0 && radar_sell_setup != EMPTY_VALUE) {
               // Sell Setup Active
               if (m1_high_shift != -1) {
                   status_msg = "[Forming] M1 Sell Pattern (Waiting 2nd)";
                   status_color = clrOrange;
               } else {
                   status_msg = "[Watching] M5 Buy Break. Waiting M1 1st Point";
                   status_color = clrGold;
               }
           }
       } else {
           status_msg = "[Watching] M5 Setup Ready. Waiting Close.";
           status_color = clrGold;
       }
   }

   // 3. Highlight near close (within 5 seconds)
   int seconds_left = (int)(time[0] + PeriodSeconds() - TimeCurrent());
   if (setup_active && seconds_left <= 5) {
       status_msg = "[Attention] Closing Soon. Check Shape!";
       status_color = clrRed;
   }
   
   // --- Information Display ---
   UpdateCountdownTimer(time[0], status_msg, status_color);

   return(rates_total);
}

//+------------------------------------------------------------------+
//| カウントダウンタイマー更新                                         |
//+------------------------------------------------------------------+
void UpdateCountdownTimer(datetime current_bar_time, string custom_status, color status_col)
{
   // 残り時間の計算
   int seconds_left = (int)(current_bar_time + PeriodSeconds() - TimeCurrent());
   if(seconds_left < 0) seconds_left = 0;
   
   int minutes = seconds_left / 60;
   int seconds = seconds_left % 60;
   
   string timer_text = "[Next Bar] " + 
                       IntegerToString(minutes) + ":" + 
                       StringFormat("%02d", seconds);
   
   color timer_color = (seconds_left <= 10) ? Timer_Warning_Color : Timer_Color;
   DrawTimer(timer_text, timer_color);
   
   // ステータス表示
   string status_text = custom_status;
   DrawStatus(status_text, status_col);
}

//+------------------------------------------------------------------+
//| タイマー描画                                                      |
//+------------------------------------------------------------------+
void DrawTimer(string text, color col)
{
   if(ObjectFind(0, timer_obj_name) < 0)
   {
      ObjectCreate(0, timer_obj_name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, timer_obj_name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, timer_obj_name, OBJPROP_XDISTANCE, Timer_X_Distance);
      ObjectSetInteger(0, timer_obj_name, OBJPROP_YDISTANCE, Timer_Y_Distance);
   }
   
   ObjectSetString(0, timer_obj_name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, timer_obj_name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, timer_obj_name, OBJPROP_FONTSIZE, Timer_FontSize);
   ObjectSetString(0, timer_obj_name, OBJPROP_FONT, "MS Gothic");
}

//+------------------------------------------------------------------+
//| ステータス描画                                                    |
//+------------------------------------------------------------------+
void DrawStatus(string text, color col)
{
   if(ObjectFind(0, status_obj_name) < 0)
   {
      ObjectCreate(0, status_obj_name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, status_obj_name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, status_obj_name, OBJPROP_XDISTANCE, Timer_X_Distance);
      // 行間調整済み（+55）
      ObjectSetInteger(0, status_obj_name, OBJPROP_YDISTANCE, Timer_Y_Distance + 55);
   }
   
   ObjectSetString(0, status_obj_name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, status_obj_name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, status_obj_name, OBJPROP_FONTSIZE, 12);
   ObjectSetString(0, status_obj_name, OBJPROP_FONT, "MS Gothic");
}

//+------------------------------------------------------------------+
//| Triggerアラート送信                                               |
//+------------------------------------------------------------------+
void SendTriggerAlert(string signal_type, datetime signal_time)
{
   string message = "[TRIGGER] Bespoji Magic: " + signal_type + " Confirmed! | " + 
                    Symbol() + " | " +
                    TimeToString(signal_time, TIME_DATE|TIME_MINUTES);
   
   if(Enable_Sound_Alert) Alert(message);
   Print(message);
   if(Enable_Mobile_Alert) SendNotification(message);
}

