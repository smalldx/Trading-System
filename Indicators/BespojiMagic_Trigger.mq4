//+------------------------------------------------------------------+
//|                                       BespojiMagic_Trigger.mq4   |
//|                    べすぽじの魔術 - 足確定タイミング執行（Trigger）  |
//|                         Copyright 2026, Expert MQL4 Developer    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Expert MQL4 Developer"
#property link      ""
#property version   "2.20"
#property strict
#property indicator_chart_window
#property indicator_buffers 2

// インジケーターバッファ
double BuySignalBuffer[];      // Buffer 0: 買いシグナル
double SellSignalBuffer[];     // Buffer 1: 売りシグナル

//--- 入力パラメータ ---

// Radar設定
input string Radar_Indicator_Name    = "BespojiMagic_Radar";  // Radarインジケーター名

// 執行ロジック設定
input bool   Use_M1_Confirmation     = true;                  // M1ダブルボトム確認（M1チャート専用）
input double Double_Pattern_Pips     = 1.5;                   // (旧仕様) 判定誤差Pips

// Radarパラメータ（Radarと設定を合わせる必要があります）
input int    BB_Period               = 21;                    // BB期間
input double BB_Deviation            = 1.0;                   // BB偏差
input int    BB_AppliedPrice         = PRICE_CLOSE;           // 適用価格
input int    Lookback_Period         = 20;                    // 高値安値確認期間
input int    Break_Validity          = 20;                    // ブレイク有効期限(足数)
input bool   Enable_H1_Filter        = false;                 // H1 MAフィルター有効
input int    H1_MA_Period            = 21;                    // H1 MA期間
input bool   Show_TP_SL_Lines        = true;                  // TP/SLライン表示
input double SL_Offset_Pips          = 2.0;                   // SLオフセットPips
input color  TP_Line_Color           = clrAqua;                // TPラインの色
input color  SL_Line_Color           = clrRed;                 // SLラインの色
input bool   Enable_Sound_Alert      = true;                  // アラート音
input bool   Enable_Mobile_Alert     = false;                 // モバイル通知
input color  Buy_Arrow_Color         = clrLime;                // Radar買い矢印色(iCustom用)
input color  Sell_Arrow_Color        = clrRed;                 // Radar売り矢印色(iCustom用)
input int    Arrow_Size              = 2;                     // Radar矢印サイズ(iCustom用)
input color  BB_Upper_Color          = clrDodgerBlue;         // BB上限色
input color  BB_Middle_Color         = clrYellow;             // BB中央色
input color  BB_Lower_Color          = clrDodgerBlue;         // BB下限色
input int    BB_Line_Width           = 1;                     // BBライン幅

// 表示設定
input color  Timer_Color             = clrWhite;              // カウントダウン通常色
input color  Timer_Warning_Color     = clrRed;                // カウントダウン警告色
input int    Timer_FontSize          = 24;                    // タイマー文字サイズ
input int    Timer_X_Distance        = 200;                   // 表示位置(X)
input int    Timer_Y_Distance        = 50;                    // 表示位置(Y)

// 矢印設定（Trigger独自）
input color  Trigger_Buy_Arrow_Color = clrLime;               // 買い確定サイン色
input color  Trigger_Sell_Arrow_Color = clrRed;                // 売り確定サイン色
input int    Trigger_Arrow_Size      = 3;                     // 確定サインサイズ

//--- グローバル変数 ---
string timer_obj_name = "BespojiTrigger_Timer";
string status_obj_name = "BespojiTrigger_Status";// アラート送信済み管理
datetime last_buy_alert_time = 0;
datetime last_sell_alert_time = 0;

// ラインの名前（管理用）
string buy_tp_line_name = "BespojiTrigger_BuyTP";
string buy_sl_line_name = "BespojiTrigger_BuySL";
string sell_tp_line_name = "BespojiTrigger_SellTP";
string sell_sl_line_name = "BespojiTrigger_SellSL";

//+------------------------------------------------------------------+
//| カスタムインジケーター初期化関数                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BuySignalBuffer);
   SetIndexBuffer(1, SellSignalBuffer);
   
   SetIndexStyle(0, DRAW_ARROW, EMPTY, Trigger_Arrow_Size, Trigger_Buy_Arrow_Color);
   SetIndexArrow(0, 233);
   SetIndexStyle(1, DRAW_ARROW, EMPTY, Trigger_Arrow_Size, Trigger_Sell_Arrow_Color);
   SetIndexArrow(1, 234);
   
   IndicatorShortName("Bespoji Magic Trigger v2.2");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   // タイマーとステータス表示を削除
   ObjectDelete(0, timer_obj_name);
   ObjectDelete(0, status_obj_name);
   DeleteTPSLLines();
}

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
   // 1. Radar状態取得 (M5 Shift 0)
   double radar_buy_setup = iCustom(NULL, PERIOD_M5, Radar_Indicator_Name,
                                    BB_Period, BB_Deviation, BB_AppliedPrice,
                                    Lookback_Period, Break_Validity,
                                    Enable_H1_Filter, H1_MA_Period,
                                    Show_TP_SL_Lines, SL_Offset_Pips, TP_Line_Color, SL_Line_Color,
                                    Enable_Sound_Alert, Enable_Mobile_Alert,
                                    Buy_Arrow_Color, Sell_Arrow_Color, Arrow_Size,
                                    BB_Upper_Color, BB_Middle_Color, BB_Lower_Color, BB_Line_Width,
                                    5, 0);

   double radar_sell_setup = iCustom(NULL, PERIOD_M5, Radar_Indicator_Name,
                                     BB_Period, BB_Deviation, BB_AppliedPrice,
                                     Lookback_Period, Break_Validity,
                                     Enable_H1_Filter, H1_MA_Period,
                                     Show_TP_SL_Lines, SL_Offset_Pips, TP_Line_Color, SL_Line_Color,
                                     Enable_Sound_Alert, Enable_Mobile_Alert,
                                     Buy_Arrow_Color, Sell_Arrow_Color, Arrow_Size,
                                     BB_Upper_Color, BB_Middle_Color, BB_Lower_Color, BB_Line_Width,
                                     6, 0);

   ArrayInitialize(BuySignalBuffer, EMPTY_VALUE);
   ArrayInitialize(SellSignalBuffer, EMPTY_VALUE);

   string status_msg = "[Standby] Waiting for Setup";
   color status_color = clrGray;

   if (Use_M1_Confirmation && Period() == PERIOD_M1)
   {
      // --- 買いロジック (M1 Center Cross + Return -1s) ---
      if (radar_buy_setup != 0 && radar_buy_setup != EMPTY_VALUE)
      {
         status_msg = "[Watching] Buy Setup Active. Waiting Mid-Cross";
         status_color = clrGold;

         bool has_crossed_mid = false;
         int start_shift = -1;
         
         // 1点目（セットアップ開始）を探す
         for(int k=1; k<100; k++) {
            double setup = iCustom(NULL, PERIOD_M5, Radar_Indicator_Name,
                                    BB_Period, BB_Deviation, BB_AppliedPrice,
                                    Lookback_Period, Break_Validity,
                                    Enable_H1_Filter, H1_MA_Period,
                                    Show_TP_SL_Lines, SL_Offset_Pips, TP_Line_Color, SL_Line_Color,
                                    Enable_Sound_Alert, Enable_Mobile_Alert,
                                    Buy_Arrow_Color, Sell_Arrow_Color, Arrow_Size,
                                    BB_Upper_Color, BB_Middle_Color, BB_Lower_Color, BB_Line_Width,
                                    5, k);
            if (setup == 0 || setup == EMPTY_VALUE) {
               start_shift = iBarShift(NULL, PERIOD_M1, iTime(NULL, PERIOD_M5, k-1));
               break;
            }
         }

         if (start_shift != -1) {
            // 中央線(Mid)を超えたか確認
            for(int m=start_shift; m>=1; m--) {
               double mid = iBands(NULL, PERIOD_M1, BB_Period, BB_Deviation, 0, BB_AppliedPrice, MODE_MAIN, m);
               if (iClose(NULL, PERIOD_M1, m) > mid) {
                  has_crossed_mid = true;
                  break;
               }
            }
            
            if (has_crossed_mid) {
               status_msg = "[Forming] Mid Crossed. Waiting -1s Return";
               status_color = clrOrange;
               
               // 現在の足(Shift 1)が -1シグマ付近か
               double sigma_1_low = iBands(NULL, PERIOD_M1, BB_Period, 1.0, 0, BB_AppliedPrice, MODE_LOWER, 1);
               if (iLow(NULL, PERIOD_M1, 1) <= sigma_1_low && iClose(NULL, PERIOD_M1, 1) > iOpen(NULL, PERIOD_M1, 1)) {
                  if (rates_total > prev_calculated) {
                     BuySignalBuffer[1] = low[1] - (30 * Point);
                     if (last_buy_alert_time != time[1]) {
                        SendTriggerAlert("M1 Double-Shape Buy", time[1]);
                        last_buy_alert_time = time[1];
                        if (Show_TP_SL_Lines) DrawBuyTPSLLines();
                     }
                  }
               }
            }
         }
      }

      // --- 売りロジック ---
      if (radar_sell_setup != 0 && radar_sell_setup != EMPTY_VALUE)
      {
         status_msg = "[Watching] Sell Setup Active. Waiting Mid-Cross";
         status_color = clrGold;

         bool has_crossed_mid = false;
         int start_shift = -1;
         
         for(int k=1; k<100; k++) {
            double setup = iCustom(NULL, PERIOD_M5, Radar_Indicator_Name,
                                    BB_Period, BB_Deviation, BB_AppliedPrice,
                                    Lookback_Period, Break_Validity,
                                    Enable_H1_Filter, H1_MA_Period,
                                    Show_TP_SL_Lines, SL_Offset_Pips, TP_Line_Color, SL_Line_Color,
                                    Enable_Sound_Alert, Enable_Mobile_Alert,
                                    Buy_Arrow_Color, Sell_Arrow_Color, Arrow_Size,
                                    BB_Upper_Color, BB_Middle_Color, BB_Lower_Color, BB_Line_Width,
                                    6, k);
            if (setup == 0 || setup == EMPTY_VALUE) {
               start_shift = iBarShift(NULL, PERIOD_M1, iTime(NULL, PERIOD_M5, k-1));
               break;
            }
         }

         if (start_shift != -1) {
            for(int m=start_shift; m>=1; m--) {
               double mid = iBands(NULL, PERIOD_M1, BB_Period, BB_Deviation, 0, BB_AppliedPrice, MODE_MAIN, m);
               if (iClose(NULL, PERIOD_M1, m) < mid) {
                  has_crossed_mid = true;
                  break;
               }
            }
            
            if (has_crossed_mid) {
               status_msg = "[Forming] Mid Crossed. Waiting +1s Return";
               status_color = clrOrange;
               
               double sigma_1_high = iBands(NULL, PERIOD_M1, BB_Period, 1.0, 0, BB_AppliedPrice, MODE_UPPER, 1);
               if (iHigh(NULL, PERIOD_M1, 1) >= sigma_1_high && iClose(NULL, PERIOD_M1, 1) < iOpen(NULL, PERIOD_M1, 1)) {
                  if (rates_total > prev_calculated) {
                     SellSignalBuffer[1] = high[1] + (30 * Point);
                     if (last_sell_alert_time != time[1]) {
                        SendTriggerAlert("M1 Double-Shape Sell", time[1]);
                        last_sell_alert_time = time[1];
                        if (Show_TP_SL_Lines) DrawSellTPSLLines();
                     }
                  }
               }
            }
         }
      }
   }
   else 
   {
      // (M1以外または設定オフ時の従来処理)
      status_msg = "[Watching] M5 Setup. Waiting Close.";
      status_color = clrGold;
      // ... 略 ...
   }

   int seconds_left = (int)(time[0] + PeriodSeconds() - TimeCurrent());
   if (radar_buy_setup != 0 || radar_sell_setup != 0) {
      if (seconds_left <= 5) {
         status_msg = "[Attention] Closing Soon!";
         status_color = clrRed;
      }
   }
   
   UpdateCountdownTimer(time[0], status_msg, status_color);
   return(rates_total);
}

void UpdateCountdownTimer(datetime current_bar_time, string custom_status, color status_col)
{
   int seconds_left = (int)(current_bar_time + PeriodSeconds() - TimeCurrent());
   if(seconds_left < 0) seconds_left = 0;
   DrawTimer("[Next Bar] " + IntegerToString(seconds_left/60) + ":" + StringFormat("%02d", seconds_left%60), (seconds_left <= 10) ? clrRed : clrWhite);
   DrawStatus(custom_status, status_col);
}

void DrawTimer(string text, color col)
{
   if(ObjectFind(0, timer_obj_name) < 0) {
      ObjectCreate(0, timer_obj_name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, timer_obj_name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, timer_obj_name, OBJPROP_XDISTANCE, Timer_X_Distance);
      ObjectSetInteger(0, timer_obj_name, OBJPROP_YDISTANCE, Timer_Y_Distance);
   }
   ObjectSetString(0, timer_obj_name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, timer_obj_name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, timer_obj_name, OBJPROP_FONTSIZE, Timer_FontSize);
}

void DrawStatus(string text, color col)
{
   if(ObjectFind(0, status_obj_name) < 0) {
      ObjectCreate(0, status_obj_name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, status_obj_name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, status_obj_name, OBJPROP_XDISTANCE, Timer_X_Distance);
      ObjectSetInteger(0, status_obj_name, OBJPROP_YDISTANCE, Timer_Y_Distance + 55);
   }
   ObjectSetString(0, status_obj_name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, status_obj_name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, status_obj_name, OBJPROP_FONTSIZE, 12);
}

void SendTriggerAlert(string signal_type, datetime signal_time)
{
   string message = "[TRIGGER] " + signal_type + " | " + Symbol() + " | " + TimeToString(signal_time, TIME_DATE|TIME_MINUTES);
   if(Enable_Sound_Alert) Alert(message);
   if(Enable_Mobile_Alert) SendNotification(message);
}

//+------------------------------------------------------------------+
//| M5基準の買いTP/SLライン描画                                       |
//+------------------------------------------------------------------+
void DrawBuyTPSLLines()
{
   DeleteTPSLLines();
   
   double pip_multiplier = (Digits % 2 == 1) ? 10.0 : 1.0;
   
   // SL: M5の過去Lookback_Period内の最安値 - Offset
   int m5_lowest_idx = iLowest(NULL, PERIOD_M5, MODE_LOW, Lookback_Period, 1);
   double sl_price = iLow(NULL, PERIOD_M5, m5_lowest_idx) - (SL_Offset_Pips * Point * pip_multiplier);
   
   // TP: M5のボリンジャーバンド上限 (+2σ)
   double tp_price = iBands(NULL, PERIOD_M5, BB_Period, BB_Deviation, 0, BB_AppliedPrice, MODE_UPPER, 0);
   
   ObjectCreate(0, buy_sl_line_name, OBJ_HLINE, 0, 0, sl_price);
   ObjectSetInteger(0, buy_sl_line_name, OBJPROP_COLOR, SL_Line_Color);
   ObjectSetInteger(0, buy_sl_line_name, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetString(0, buy_sl_line_name, OBJPROP_TEXT, " Buy SL (M5)");
   
   ObjectCreate(0, buy_tp_line_name, OBJ_HLINE, 0, 0, tp_price);
   ObjectSetInteger(0, buy_tp_line_name, OBJPROP_COLOR, TP_Line_Color);
   ObjectSetInteger(0, buy_tp_line_name, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetString(0, buy_tp_line_name, OBJPROP_TEXT, " Buy TP (M5)");
}

//+------------------------------------------------------------------+
//| M5基準の売りTP/SLライン描画                                       |
//+------------------------------------------------------------------+
void DrawSellTPSLLines()
{
   DeleteTPSLLines();
   
   double pip_multiplier = (Digits % 2 == 1) ? 10.0 : 1.0;
   
   // SL: M5の過去Lookback_Period内の最高値 + Offset
   int m5_highest_idx = iHighest(NULL, PERIOD_M5, MODE_HIGH, Lookback_Period, 1);
   double sl_price = iHigh(NULL, PERIOD_M5, m5_highest_idx) + (SL_Offset_Pips * Point * pip_multiplier);
   
   // TP: M5のボリンジャーバンド下限 (-2σ)
   double tp_price = iBands(NULL, PERIOD_M5, BB_Period, BB_Deviation, 0, BB_AppliedPrice, MODE_LOWER, 0);
   
   ObjectCreate(0, sell_sl_line_name, OBJ_HLINE, 0, 0, sl_price);
   ObjectSetInteger(0, sell_sl_line_name, OBJPROP_COLOR, SL_Line_Color);
   ObjectSetInteger(0, sell_sl_line_name, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetString(0, sell_sl_line_name, OBJPROP_TEXT, " Sell SL (M5)");
   
   ObjectCreate(0, sell_tp_line_name, OBJ_HLINE, 0, 0, tp_price);
   ObjectSetInteger(0, sell_tp_line_name, OBJPROP_COLOR, TP_Line_Color);
   ObjectSetInteger(0, sell_tp_line_name, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetString(0, sell_tp_line_name, OBJPROP_TEXT, " Sell TP (M5)");
}

//+------------------------------------------------------------------+
//| ライン削除                                                       |
//+------------------------------------------------------------------+
void DeleteTPSLLines()
{
   ObjectDelete(0, buy_tp_line_name);
   ObjectDelete(0, buy_sl_line_name);
   ObjectDelete(0, sell_tp_line_name);
   ObjectDelete(0, sell_sl_line_name);
}
