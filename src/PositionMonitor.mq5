// Read-only TP/SL totals. No trading functions, DLLs, network or advertisements.
#property version   "1.39"
#property description "Read-only TP/SL totals for open positions."
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots 5
#property indicator_type1 DRAW_NONE
#property indicator_type2 DRAW_NONE
#property indicator_label1 "TP total"
#property indicator_label2 "SL total"
#property indicator_type3 DRAW_NONE
#property indicator_type4 DRAW_NONE
#property indicator_type5 DRAW_NONE
#property indicator_label3 "Break even rate"
#property indicator_label4 "Stop out estimate"
#property indicator_label5 "Margin level percent"

input bool InpCurrentSymbolOnly=true;        // 現在のチャート銘柄のみ
input bool InpShowAccountTotals=true;         // 全銘柄のTP/SL予定額も表示
input bool InpIncludeSwap=true;              // 現在までのスワップを含める
input double InpExitCommissionPerLot=0.0;    // 決済時の手数料/lot（口座通貨・片道）
input ENUM_BASE_CORNER InpCorner=CORNER_LEFT_LOWER; // 表示する隅
input int InpX=15;                          // 左右端からの距離 px
input int InpY=25;                          // 上下端からの距離 px
input int InpFontSize=11;                   // 損益の文字サイズ
input int InpRowSpacing=0;                  // 行間 px（0=文字サイズに合わせて自動）
input string InpFont="Meiryo";              // フォント
input bool InpShowBackground=true;          // 数値の背後に背景を表示
input color InpBackgroundColor=C'22,24,29'; // 背景色
input int InpDecimals=2;                    // 小数点以下の桁数
input bool InpShowHeader=true;              // 銘柄・件数・スワップ設定
input bool InpShowJPY=false;                // 円換算も表示（気配値に換算銘柄が必要）
input bool InpShowRates=true;              // 現在価格・損益分岐・ロスカット目安
input double InpStopOutPercent=0.0;         // 0=MT5口座基準を自動取得、正数=手動のロスカット基準%
input bool InpShowMarginLevel=true;         // 現在の口座証拠金維持率
input bool InpShowAccountDetails=true;      // 残高・有効証拠金・必要証拠金・余剰証拠金
input bool InpShowCurrentProfit=true;       // 現在の口座含み損益
input color InpProfitColor=clrLimeGreen;    // 利益の色
input color InpLossColor=clrRed;             // 損失の色
input color InpInfoColor=clrWhite;          // 補助文字の色
input color InpWarningColor=clrOrange;      // 未設定・計算不可の色
input color InpCurrentProfitColor=clrDodgerBlue; // 現在損益がプラスの色
input color InpCurrentLossColor=clrRed;     // 現在損益がマイナスの色
input color InpMarginCallColor=clrRed;       // マージンコール以下の維持率の色
input double InpMarginWarningPercent=400.0;  // 維持率の警戒表示基準 %
input color InpMarginWarningColor=clrYellow; // 警戒基準未満の維持率の色
input double InpTrialTP=0.0;                 // 仮TP価格（0=試算しない）
input double InpTrialSL=0.0;                 // 仮SL価格（0=試算しない）
input bool InpScenarioAlignRight=false;     // 試算パネルを右上に表示
input int InpScenarioX=15;                  // 試算パネルの左右端からの距離 px
input int InpScenarioY=25;                  // 試算パネルの上端からの距離 px

double TPBuffer[],SLBuffer[];
double BEBuffer[],SOBuffer[],MarginBuffer[];
double break_even=EMPTY_VALUE,stop_out=EMPTY_VALUE,margin_level=EMPTY_VALUE;
string prefix;
double total_tp=0,total_sl=0;
bool valid_tp=true,valid_sl=true;
double account_tp=0,account_sl=0;
bool valid_account_tp=true,valid_account_sl=true;
int total_positions=0;
int account_positions=0;
string account_currency;
uint last_layout_tick=0;
bool layout_dirty=true;
bool layout_visible=false;
bool layout_measure_requested=false;
bool monitor_hidden=false;
bool scenario_hidden=false;
int max_background_width=0;
string scenario_position_key="";
uint last_scenario_check=0;
#include "PositionScenarioPanel.mqh"
string ScenarioPrefix()
{
   return "PositionScenario_"+IntegerToString(ChartID())+"_";
}
void SetPanelVisibility(const string target_prefix,const bool hidden)
{
   int count=ObjectsTotal(0);
   for(int i=0;i<count;i++)
   {
      string name=ObjectName(0,i);
      if(StringFind(name,target_prefix)!=0 ||
         name==prefix+"toggle_monitor" || name==prefix+"toggle_scenario") continue;
      long periods=hidden ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS;
      if(ObjectGetInteger(0,name,OBJPROP_TIMEFRAMES)!=periods)
         ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES,periods);
   }
}
void SetToggleText(const string suffix,const bool hidden)
{
   string noun=suffix=="monitor" ? "監視" : "試算";
   string name=prefix+"toggle_"+suffix;
   ObjectSetString(0,name,OBJPROP_TEXT,noun+(hidden ? "を表示" : "を隠す"));
   ObjectSetInteger(0,name,OBJPROP_STATE,false);
}
void CreateToggleButton(const string suffix,const int xdistance)
{
   string name=prefix+"toggle_"+suffix;
   if(!ObjectCreate(0,name,OBJ_BUTTON,0,0,0)) return;
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,xdistance);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,2);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,80);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,20);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,C'45,48,55');
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,C'100,104,110');
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,9);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,1000);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetString(0,name,OBJPROP_FONT,InpFont);
   SetToggleText(suffix,false);
}
int DisplayRows()
{
   return (InpShowHeader ? 1 : 0)+2+
          (InpCurrentSymbolOnly && InpShowAccountTotals ? 2 : 0)+
          (InpShowRates ? 3 : 0)+(InpShowCurrentProfit ? 2 : 0)+
          (InpShowAccountDetails ? 4 : 0)+(InpShowMarginLevel ? 1 : 0);
}
void CreateBackground()
{
   if(!InpShowBackground) return;
   string name=prefix+"background";
   if(!ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0)) return;
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,100000);
   ObjectSetInteger(0,name,OBJPROP_CORNER,InpCorner);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,InpBackgroundColor);
   ObjectSetInteger(0,name,OBJPROP_COLOR,InpBackgroundColor);
   ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
}

// Round before grouping so 999.999 becomes 1,000.00.
string Grouped(const double value,const int digits)
{
   string s=DoubleToString(MathAbs(value),digits);
   int dot=StringFind(s,".");
   int end=(dot<0 ? StringLen(s) : dot);
   for(int i=end-3;i>0;i-=3)
      s=StringSubstr(s,0,i)+","+StringSubstr(s,i);
   return s;
}
string LotsText(const double lots)
{
   string fixed=DoubleToString(lots,8);
   int digits=8;
   while(digits>0 && StringGetCharacter(fixed,StringLen(fixed)-1)=='0')
   {
      fixed=StringSubstr(fixed,0,StringLen(fixed)-1);
      digits--;
   }
   return Grouped(lots,digits);
}
string ThresholdText(const double value,const bool percent,const string currency)
{
   string fixed=DoubleToString(value,4);
   int dot=StringFind(fixed,".");
   if(dot>=0)
   {
      while(StringLen(fixed)>dot+1 && StringGetCharacter(fixed,StringLen(fixed)-1)=='0')
         fixed=StringSubstr(fixed,0,StringLen(fixed)-1);
      if(StringLen(fixed)==dot+1) fixed=StringSubstr(fixed,0,dot);
   }
   int digits=(StringFind(fixed,".")>=0 ? StringLen(fixed)-StringFind(fixed,".")-1 : 0);
   return Grouped(value,digits)+(percent ? "%" : " "+currency);
}
bool ThresholdReached(const bool percent,const double level,const double equity,const double threshold)
{
   return (percent ? level : equity)<=threshold;
}
double ThresholdEquity(const bool percent,const double margin,const double threshold)
{
   return percent ? margin*threshold/100.0 : threshold;
}
string Money(const double value,const string currency,const int digits)
{
   double rounded=NormalizeDouble(value,digits);
   return (rounded<0 ? "-" : (rounded>0 ? "+" : ""))+Grouped(rounded,digits)+" "+currency;
}
string PadAmount(const string value,const int width)
{
   string result=value;
   while(StringLen(result)<width) result=" "+result;
   return result;
}
bool LinearMode(const ENUM_SYMBOL_CALC_MODE mode)
{
   return mode==SYMBOL_CALC_MODE_FOREX || mode==SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE ||
          mode==SYMBOL_CALC_MODE_CFD || mode==SYMBOL_CALC_MODE_CFDLEVERAGE ||
          mode==SYMBOL_CALC_MODE_CFDINDEX || mode==SYMBOL_CALC_MODE_EXCH_STOCKS ||
          mode==SYMBOL_CALC_MODE_EXCH_STOCKS_MOEX;
}
// Indicators cannot use OrderCalcProfit. Linear contracts in account currency
// are calculated directly; other linear contracts/futures use account-currency tick values.
bool Estimate(const string symbol,const bool buy,const double lots,
              const double entry,const double exit_price,double &value)
{
   double delta=(buy ? exit_price-entry : entry-exit_price);
   ENUM_SYMBOL_CALC_MODE mode=(ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(symbol,SYMBOL_TRADE_CALC_MODE);
   bool linear=LinearMode(mode);
   bool futures=mode==SYMBOL_CALC_MODE_FUTURES || mode==SYMBOL_CALC_MODE_EXCH_FUTURES ||
                mode==SYMBOL_CALC_MODE_EXCH_FUTURES_FORTS;
   if(!linear && !futures) return false;
   if(linear && SymbolInfoString(symbol,SYMBOL_CURRENCY_PROFIT)==account_currency)
   {
      double contract=SymbolInfoDouble(symbol,SYMBOL_TRADE_CONTRACT_SIZE);
      if(contract<=0) return false;
      value=delta*lots*contract;
      return MathIsValidNumber(value);
   }
   if(delta==0) { value=0; return true; }
   double size=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   double tick=SymbolInfoDouble(symbol,delta>0 ? SYMBOL_TRADE_TICK_VALUE_PROFIT : SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(size<=0 || tick<=0) return false;
   value=delta/size*tick*lots;
   return MathIsValidNumber(value);
}
// Conversion is display-only, using already selected symbols (no Market Watch mutations).
bool ToJPY(const double amount,double &yen,datetime &quote_time)
{
   if(account_currency=="JPY") { yen=amount; quote_time=TimeCurrent(); return true; }
   string chosen="";
   double rate=0;
   quote_time=0;
   for(int i=0;i<SymbolsTotal(true);i++)
   {
      string s=SymbolName(i,true);
      string base=SymbolInfoString(s,SYMBOL_CURRENCY_BASE);
      string profit=SymbolInfoString(s,SYMBOL_CURRENCY_PROFIT);
      bool direct=(base==account_currency && profit=="JPY");
      bool inverse=(base=="JPY" && profit==account_currency);
      if(!direct && !inverse) continue;
      MqlTick t;
      if(!SymbolInfoTick(s,t) || t.bid<=0 || t.ask<=0) continue;
      if(t.time<quote_time) continue;
      quote_time=t.time;
      chosen=s;
      // Positive amounts sell account currency; negative amounts buy it.
      rate=direct ? (amount>=0 ? t.bid : t.ask) : 1.0/(amount>=0 ? t.ask : t.bid);
   }
   if(chosen=="") return false;
   yen=amount*rate;
   return MathIsValidNumber(yen);
}
bool PutLabel(const string suffix,const string text,const int row,const color colour,const int size)
{
   string name=prefix+suffix;
   bool created=ObjectFind(0,name)<0;
   if(created && !ObjectCreate(0,name,OBJ_LABEL,0,0,0)) return false;
   if(created)
   {
      layout_dirty=true;
      layout_measure_requested=false;
      // Keep every part off-screen until all labels have measurable widths.
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,100000);
   }
   // Set text immediately after creation so MT5 never paints the default "Label" text.
   if(created) ObjectSetString(0,name,OBJPROP_TEXT,text);
   bool bottom=(InpCorner==CORNER_LEFT_LOWER || InpCorner==CORNER_RIGHT_LOWER);
   bool right=(InpCorner==CORNER_RIGHT_UPPER || InpCorner==CORNER_RIGHT_LOWER);
   ENUM_ANCHOR_POINT anchor=bottom ? (right ? ANCHOR_RIGHT_LOWER : ANCHOR_LEFT_LOWER)
                                   : (right ? ANCHOR_RIGHT_UPPER : ANCHOR_LEFT_UPPER);
   int spacing=(int)MathMax(InpRowSpacing,InpFontSize*2);
   int rows=DisplayRows();
   int distance=(int)MathMax(0,InpY)+(bottom ? rows-1-row : row)*spacing;
   if(created)
   {
      ObjectSetInteger(0,name,OBJPROP_CORNER,InpCorner);
      ObjectSetInteger(0,name,OBJPROP_ANCHOR,anchor);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,distance);
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,size);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,name,OBJPROP_BACK,false);
      ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES,monitor_hidden ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);
      ObjectSetString(0,name,OBJPROP_FONT,InpFont);
   }
   if(created || ObjectGetInteger(0,name,OBJPROP_COLOR)!=(long)colour)
      ObjectSetInteger(0,name,OBJPROP_COLOR,colour);
   if(!created)
   {
      string previous_text=ObjectGetString(0,name,OBJPROP_TEXT);
      if(previous_text!=text)
      {
         if(StringLen(previous_text)!=StringLen(text))
         {
            layout_dirty=true;
            layout_measure_requested=false;
         }
         ObjectSetString(0,name,OBJPROP_TEXT,text);
      }
   }
   string tip="設定価格での決済見積り。予約注文・滑り・将来Swap・支払済み手数料は含みません。";
   if(suffix=="header") tip=InpIncludeSwap ?
      "スワップ込: 現在までに発生したスワップをTP/SL合計と損益分岐に含めます。将来分は含みません。" :
      "スワップ除外: TP/SL合計と損益分岐では発生済みスワップを除外します。口座情報はMT5の値をそのまま表示します。";
   if(suffix=="so") tip="最初の強制決済の推定開始価格。現在の必要証拠金・他銘柄損益・為替・スプレッドを固定し、途中のSL/TP決済を無視した仮定です。全件決済価格ではありません。価格基準はショートのみAsk、ロングのみBid、両建ては固定スプレッドのBid換算。";
   if(suffix=="be") tip="現在チャート銘柄の合計損益がゼロになる決済価格。Swap設定と入力済み決済手数料を反映。価格基準はショートのみAsk、ロングのみBid、両建ては固定スプレッドのBid換算。";
   if(suffix=="price") tip="現在チャート銘柄の価格。損益分岐・ロスカットとの比較のため、これらの推定レートと同じ価格基準を表示します。";
   if(suffix=="account_tp" || suffix=="account_sl")
      tip="口座内の全保有銘柄がそれぞれ現在設定のTP/SLで決済された場合の合計。未設定は合計から除外し、黄色で警告します。";
   if(suffix=="symbol_profit") tip="現在チャート銘柄の含み損益。各保有ポジションのPOSITION_PROFITの合計で、スワップは含みません。右側は口座残高に対する増減率です。";
   if(suffix=="current_profit") tip="口座全体の現在の含み損益。MT5のACCOUNT_PROFITを表示し、スワップは含みません。右側は口座残高に対する増減率です。";
   if(suffix=="balance") tip="口座全体の残高。未決済ポジションの損益は含みません。";
   if(suffix=="equity") tip="口座全体の有効証拠金。現在の未決済損益を反映したMT5の口座値です。";
   if(suffix=="used_margin") tip="口座全体の必要証拠金。MT5の口座値です。";
   if(suffix=="free_margin") tip="口座全体の余剰証拠金。MT5の口座値です。";
   if(suffix=="margin") tip="口座全体の証拠金維持率。有効証拠金÷必要証拠金×100。400%未満は黄色、マージンコール基準以下は赤で表示します。表示するストップアウト基準は口座設定から取得します。口座基準が金額の場合は有効証拠金でマージンコールを判定します。";
   if(created || ObjectGetString(0,name,OBJPROP_TOOLTIP)!=tip)
      ObjectSetString(0,name,OBJPROP_TOOLTIP,tip);
   return true;
}
string SignedGrouped(const double value,const int digits)
{
   double rounded=NormalizeDouble(value,digits);
   return (rounded>0 ? "+" : (rounded<0 ? "-" : ""))+Grouped(rounded,digits);
}
bool RatioValue(const double value,const double balance,string &ratio)
{
   ratio="";
   if(balance<=0 || !MathIsValidNumber(balance)) return false;
   ratio=SignedGrouped(value/balance*100.0,2);
   return true;
}
bool RateDifferenceValues(const double target,const double current,string &rate_difference,string &pips)
{
   rate_difference=""; pips="";
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(point<=0) return false;
   double pip_size=point*((digits==3 || digits==5) ? 10.0 : 1.0);
   if(pip_size<=0) return false;
   double difference=target-current;
   rate_difference=SignedGrouped(difference,digits);
   pips=SignedGrouped(difference/pip_size,1);
   return true;
}
string RowText(const string title,const double value,const int errors)
{
   if(errors>0) return title+"  計算不可 ("+IntegerToString(errors)+"件)";
   string text=title+"  "+Money(value,account_currency,InpDecimals);
   if(InpShowJPY && (total_positions>0 || account_positions>0))
   {
      double yen;
      datetime stamp;
      if(ToJPY(value,yen,stamp))
      {
         text+="  /  "+Money(yen,"JPY",0);
         if(TimeCurrent()-stamp>3600) text+=" [参考レート "+TimeToString(stamp,TIME_DATE|TIME_MINUTES)+"]";
      }
      else text+="  /  JPY換算不可";
   }
   return text;
}
// Keep numbers separate from units and annotations; all rows share one numeric column.
void SplitNumber(const string text,string &number,string &note)
{
   int i=0;
   for(;i<StringLen(text);i++)
   {
      ushort c=StringGetCharacter(text,i);
      if(!((c>='0' && c<='9') || c=='+' || c=='-' || c==',' || c=='.')) break;
   }
   if(i==0) { number=text; note=""; return; }
   number=StringSubstr(text,0,i);
   note=StringSubstr(text,i);
   StringTrimLeft(note);
}
void RenderValueRow(const string suffix,const string title,const string text,const int row,const color colour)
{
   string number,note;
   SplitNumber(text,number,note);
   string unit=note,tail="";
   int separator=StringFind(note," ストップアウト ");
   if(separator>=0)
   {
      unit=StringSubstr(note,0,separator);
      StringTrimRight(unit);
      tail=StringSubstr(note,separator+1);
   }
   PutLabel(suffix,title,row,colour,InpFontSize);
   PutLabel(suffix+"_value",number,row,colour,InpFontSize);
   string tip=ObjectGetString(0,prefix+suffix,OBJPROP_TOOLTIP);
   ObjectSetString(0,prefix+suffix+"_value",OBJPROP_TOOLTIP,tip);
   // Never create empty labels: MT5 can display its initial "Label" text.
   if(unit!="")
   {
      PutLabel(suffix+"_note",unit,row,colour,InpFontSize);
      ObjectSetString(0,prefix+suffix+"_note",OBJPROP_TOOLTIP,tip);
   }
   else if(ObjectFind(0,prefix+suffix+"_note")>=0)
      ObjectDelete(0,prefix+suffix+"_note");
   if(tail!="")
   {
      PutLabel(suffix+"_tail",tail,row,colour,InpFontSize);
      ObjectSetString(0,prefix+suffix+"_tail",OBJPROP_TOOLTIP,tip);
   }
   else if(ObjectFind(0,prefix+suffix+"_tail")>=0)
      ObjectDelete(0,prefix+suffix+"_tail");
}
void DeleteAnnotation(const string suffix)
{
   string parts[5]={"_open","_value","_middle","_pips","_suffix"};
   for(int i=0;i<5;i++)
   {
      string name=prefix+suffix+parts[i];
      if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
   }
}
void SetRatioAnnotation(const string suffix,const double value,const double balance,
                        const int row,const color colour)
{
   string ratio;
   if(!RatioValue(value,balance,ratio)) { DeleteAnnotation(suffix+"_ratio"); return; }
   string base=suffix+"_ratio";
   PutLabel(base+"_value",ratio,row,colour,InpFontSize);
   PutLabel(base+"_suffix"," %",row,colour,InpFontSize);
   string tip=ObjectGetString(0,prefix+suffix,OBJPROP_TOOLTIP);
   ObjectSetString(0,prefix+base+"_value",OBJPROP_TOOLTIP,tip);
   ObjectSetString(0,prefix+base+"_suffix",OBJPROP_TOOLTIP,tip);
}
void SetMissingWarning(const string suffix,const int missing,const int row)
{
   string name=prefix+suffix+"_missing";
   if(missing<=0)
   {
      if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
      return;
   }
   PutLabel(suffix+"_missing","未設定 "+IntegerToString(missing)+"件・一部合計",
            row,clrYellow,InpFontSize);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,
                   "TP/SL未設定のポジションは合計損益に含めません。");
}
void SetRateAnnotation(const string suffix,const double target,const double current,
                       const int row,const color colour)
{
   string rate_difference,pips;
   if(!RateDifferenceValues(target,current,rate_difference,pips)) { DeleteAnnotation(suffix+"_rate"); return; }
   string base=suffix+"_rate";
   PutLabel(base+"_value",pips,row,colour,InpFontSize);
   PutLabel(base+"_middle"," pips ",row,colour,InpFontSize);
   PutLabel(base+"_pips",rate_difference,row,colour,InpFontSize);
   string tip=ObjectGetString(0,prefix+suffix,OBJPROP_TOOLTIP);
   string parts[3]={"_value","_middle","_pips"};
   for(int i=0;i<3;i++) ObjectSetString(0,prefix+base+parts[i],OBJPROP_TOOLTIP,tip);
}
void MoneyRows(const int first_row,const int missing_tp,const int error_tp,
               const int missing_sl,const int error_sl,
               const int account_missing_tp,const int account_error_tp,
               const int account_missing_sl,const int account_error_sl)
{
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   color tp_color=!valid_tp ? InpWarningColor : (total_tp<0 ? InpLossColor : InpProfitColor);
   color sl_color=!valid_sl ? InpWarningColor : (total_sl<0 ? InpLossColor : InpProfitColor);
   RenderValueRow("tp",InpCurrentSymbolOnly ? "TP合計(銘柄)" : "TP合計(口座)",
                  StringSubstr(RowText("",total_tp,error_tp),2),first_row,tp_color);
   RenderValueRow("sl",InpCurrentSymbolOnly ? "SL合計(銘柄)" : "SL合計(口座)",
                  StringSubstr(RowText("",total_sl,error_sl),2),first_row+1,sl_color);
   if(valid_tp) SetRatioAnnotation("tp",total_tp,balance,first_row,tp_color);
   else DeleteAnnotation("tp_ratio");
   if(valid_sl) SetRatioAnnotation("sl",total_sl,balance,first_row+1,sl_color);
   else DeleteAnnotation("sl_ratio");
   SetMissingWarning("tp",missing_tp,first_row);
   SetMissingWarning("sl",missing_sl,first_row+1);
   if(InpCurrentSymbolOnly && InpShowAccountTotals)
   {
      color account_tp_color=!valid_account_tp ? InpWarningColor :
                             (account_tp<0 ? InpLossColor : InpProfitColor);
      color account_sl_color=!valid_account_sl ? InpWarningColor :
                             (account_sl<0 ? InpLossColor : InpProfitColor);
      RenderValueRow("account_tp","TP合計(口座)",StringSubstr(RowText("",account_tp,account_error_tp),2),
                     first_row+2,account_tp_color);
      RenderValueRow("account_sl","SL合計(口座)",StringSubstr(RowText("",account_sl,account_error_sl),2),
                     first_row+3,account_sl_color);
      if(valid_account_tp) SetRatioAnnotation("account_tp",account_tp,balance,first_row+2,account_tp_color);
      else DeleteAnnotation("account_tp_ratio");
      if(valid_account_sl) SetRatioAnnotation("account_sl",account_sl,balance,first_row+3,account_sl_color);
      else DeleteAnnotation("account_sl_ratio");
      SetMissingWarning("account_tp",account_missing_tp,first_row+2);
      SetMissingWarning("account_sl",account_missing_sl,first_row+3);
   }
}
void PublishBuffers()
{
   if(ArraySize(TPBuffer)>0) TPBuffer[0]=valid_tp ? total_tp : EMPTY_VALUE;
   if(ArraySize(SLBuffer)>0) SLBuffer[0]=valid_sl ? total_sl : EMPTY_VALUE;
   if(ArraySize(BEBuffer)>0) BEBuffer[0]=break_even;
   if(ArraySize(SOBuffer)>0) SOBuffer[0]=stop_out;
   if(ArraySize(MarginBuffer)>0) MarginBuffer[0]=margin_level;
}
void DetailRow(const string suffix,const string title,const string value,const int row,const color colour)
{
   RenderValueRow(suffix,title,value,row,colour);
}
bool LabelWidthsReady()
{
   int count=ObjectsTotal(0,0,OBJ_LABEL);
   int own_labels=0;
   for(int i=0;i<count;i++)
   {
      string name=ObjectName(0,i,0,OBJ_LABEL);
      if(StringFind(name,prefix)!=0) continue;
      own_labels++;
      if(ObjectGetString(0,name,OBJPROP_TEXT)!="" &&
         ObjectGetInteger(0,name,OBJPROP_XSIZE)<=0) return false;
   }
   return own_labels>0;
}
void CreateFourDigitWidthSamples()
{
   PutLabel("width_currency"," "+account_currency,0,InpInfoColor,InpFontSize);
   int rate_digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   string samples[3]={SignedGrouped(9999.99,2),SignedGrouped(9999.9,1),
                      SignedGrouped(9999,rate_digits)};
   string kinds[3]={"ratio","pips","rate"};
   for(int i=0;i<3;i++)
   {
      PutLabel("width_"+kinds[i]+"_plus",samples[i],0,InpInfoColor,InpFontSize);
      PutLabel("width_"+kinds[i]+"_minus","-"+StringSubstr(samples[i],1),0,InpInfoColor,InpFontSize);
   }
}
int FourDigitWidth(const string kind)
{
   string base=prefix+"width_"+kind;
   return (int)MathMax(ObjectGetInteger(0,base+"_plus",OBJPROP_XSIZE),
                       ObjectGetInteger(0,base+"_minus",OBJPROP_XSIZE));
}
void FitBackground(const int reserved_width)
{
   string background=prefix+"background";
   if(ObjectFind(0,background)<0) return;
   int chart_width=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
   int chart_height=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
   bool right=(InpCorner==CORNER_RIGHT_UPPER || InpCorner==CORNER_RIGHT_LOWER);
   bool bottom=(InpCorner==CORNER_LEFT_LOWER || InpCorner==CORNER_RIGHT_LOWER);
   int left=INT_MAX,top=INT_MAX,far_right=0,far_bottom=0;
   int count=ObjectsTotal(0,0,OBJ_LABEL);
   for(int i=0;i<count;i++)
   {
      string name=ObjectName(0,i,0,OBJ_LABEL);
      if(StringFind(name,prefix)!=0 || StringFind(name,prefix+"width_")==0) continue;
      int w=(int)ObjectGetInteger(0,name,OBJPROP_XSIZE);
      int h=(int)ObjectGetInteger(0,name,OBJPROP_YSIZE);
      if(w<=0 || h<=0) continue;
      int x=(int)ObjectGetInteger(0,name,OBJPROP_XDISTANCE);
      int y=(int)ObjectGetInteger(0,name,OBJPROP_YDISTANCE);
      if(right) x=chart_width-x;
      if(bottom) y=chart_height-y;
      ENUM_ANCHOR_POINT anchor=(ENUM_ANCHOR_POINT)ObjectGetInteger(0,name,OBJPROP_ANCHOR);
      if(anchor==ANCHOR_RIGHT_UPPER || anchor==ANCHOR_RIGHT_LOWER) x-=w;
      if(anchor==ANCHOR_LEFT_LOWER || anchor==ANCHOR_RIGHT_LOWER) y-=h;
      left=(int)MathMin(left,x);
      top=(int)MathMin(top,y);
      far_right=(int)MathMax(far_right,x+w);
      far_bottom=(int)MathMax(far_bottom,y+h);
   }
   if(left==INT_MAX) return;
   const int pad=6;
   left=(int)MathMax(0,left-pad);
   top=(int)MathMax(0,top-pad);
   // Reserve the four-digit layout on the first draw. Never shrink the panel
   // when an actual value switches between three and four digits.
   max_background_width=(int)MathMax(max_background_width,
                                  MathMax(reserved_width,far_right-left+pad));
   int panel_width=(int)MathMin(chart_width,max_background_width);
   int panel_height=far_bottom-top+pad;
   ObjectSetInteger(0,background,OBJPROP_XSIZE,panel_width);
   ObjectSetInteger(0,background,OBJPROP_YSIZE,panel_height);
   ObjectSetInteger(0,background,OBJPROP_XDISTANCE,right ? panel_width : 0);
   ObjectSetInteger(0,background,OBJPROP_YDISTANCE,bottom ? chart_height-top : top);
}
void AlignDetailRows()
{
   string names[14]={"tp","sl","account_tp","account_sl","price","be","so","symbol_profit","current_profit","balance","equity","used_margin","free_margin","margin"};
   string money_names[6]={"tp","sl","account_tp","account_sl","symbol_profit","current_profit"};
   string rate_names[2]={"be","so"};
   int title_width=0,value_width=0,unit_width=0,tail_width=0;
   int money_unit_width=(int)ObjectGetInteger(0,prefix+"width_currency",OBJPROP_XSIZE);
   int ratio_value_width=0,ratio_suffix_width=0;
   int rate_value_width=0,rate_middle_width=0,rate_pips_width=0;
   for(int i=0;i<14;i++)
   {
      string name=prefix+names[i];
      if(ObjectFind(0,name)<0) continue;
      title_width=(int)MathMax(title_width,ObjectGetInteger(0,name,OBJPROP_XSIZE));
      value_width=(int)MathMax(value_width,ObjectGetInteger(0,name+"_value",OBJPROP_XSIZE));
      bool money_row=(names[i]=="tp" || names[i]=="sl" || names[i]=="account_tp" ||
                      names[i]=="account_sl" || names[i]=="symbol_profit" ||
                      names[i]=="current_profit");
      if(!money_row && ObjectFind(0,name+"_note")>=0)
         unit_width=(int)MathMax(unit_width,ObjectGetInteger(0,name+"_note",OBJPROP_XSIZE));
      if(ObjectFind(0,name+"_tail")>=0)
         tail_width=(int)MathMax(tail_width,ObjectGetInteger(0,name+"_tail",OBJPROP_XSIZE));
   }
   for(int i=0;i<6;i++)
   {
      string name=prefix+money_names[i];
      string base=name+"_ratio";
      if(ObjectFind(0,base+"_value")>=0)
      {
         ratio_value_width=(int)MathMax(ratio_value_width,ObjectGetInteger(0,base+"_value",OBJPROP_XSIZE));
         ratio_suffix_width=(int)MathMax(ratio_suffix_width,ObjectGetInteger(0,base+"_suffix",OBJPROP_XSIZE));
      }
   }
   for(int i=0;i<2;i++)
   {
      string base=prefix+rate_names[i]+"_rate";
      if(ObjectFind(0,base+"_value")>=0)
      {
         rate_value_width=(int)MathMax(rate_value_width,ObjectGetInteger(0,base+"_value",OBJPROP_XSIZE));
         rate_middle_width=(int)MathMax(rate_middle_width,ObjectGetInteger(0,base+"_middle",OBJPROP_XSIZE));
         rate_pips_width=(int)MathMax(rate_pips_width,ObjectGetInteger(0,base+"_pips",OBJPROP_XSIZE));
      }
   }
   // Reserve four integer digits so a change from 999 to 1,000 does not shift columns.
   ratio_value_width=(int)MathMax(ratio_value_width,FourDigitWidth("ratio"));
   rate_value_width=(int)MathMax(rate_value_width,FourDigitWidth("pips"));
   rate_pips_width=(int)MathMax(rate_pips_width,FourDigitWidth("rate"));
   int annotation_value_width=(int)MathMax(ratio_value_width,rate_value_width);
   // Initial fallback sizes are replaced by actual rendered widths on the next refresh.
   if(title_width<=0) title_width=InpFontSize*7;
   if(value_width<=0) value_width=InpFontSize*9;
   int gap=(int)MathMax(10,InpFontSize);
   bool right=(InpCorner==CORNER_RIGHT_UPPER || InpCorner==CORNER_RIGHT_LOWER);
   bool bottom=(InpCorner==CORNER_LEFT_LOWER || InpCorner==CORNER_RIGHT_LOWER);
   ENUM_ANCHOR_POINT left_anchor=bottom ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER;
   ENUM_ANCHOR_POINT right_anchor=bottom ? ANCHOR_RIGHT_LOWER : ANCHOR_RIGHT_UPPER;
   int generic_width=(int)MathMax(unit_width,money_unit_width)+(tail_width>0 ? gap+tail_width : 0);
   if(ObjectFind(0,prefix+"margin_tail")>=0)
   {
      int margin_tail_width=(int)ObjectGetInteger(0,prefix+"margin_tail",OBJPROP_XSIZE);
      generic_width=(int)MathMax(generic_width,money_unit_width+gap+margin_tail_width);
   }
   int ratio_width=money_unit_width+(ratio_value_width>0 ? gap+annotation_value_width+ratio_suffix_width : 0);
   int rate_width=(rate_value_width>0 ? money_unit_width+gap+annotation_value_width+rate_middle_width+rate_pips_width : 0);
   int suffix_width=(int)MathMax(generic_width,MathMax(ratio_width,rate_width));
   int width=title_width+gap+value_width+(suffix_width>0 ? gap+suffix_width : 0);
   int origin=(int)MathMax(0,InpX)+(right ? width : 0);
   int direction=(right ? -1 : 1);
   // Bring the main values closer to the auxiliary column without moving the
   // aligned percent, pips and rate-difference annotations.
   const int value_shift=20;
   int numeric_end=origin+direction*(title_width+gap+value_width+value_shift);
   int note_start=numeric_end+direction*gap;
   int annotation_start=note_start+direction*(money_unit_width+gap-value_shift);
   if(ObjectFind(0,prefix+"header")>=0)
      ObjectSetInteger(0,prefix+"header",OBJPROP_XDISTANCE,(int)MathMax(0,InpX));
   for(int i=0;i<14;i++)
   {
      string name=prefix+names[i];
      if(ObjectFind(0,name)<0) continue;
      ObjectSetInteger(0,name,OBJPROP_ANCHOR,left_anchor);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,origin);
      ObjectSetInteger(0,name+"_value",OBJPROP_ANCHOR,right_anchor);
      ObjectSetInteger(0,name+"_value",OBJPROP_XDISTANCE,numeric_end);
      if(ObjectFind(0,name+"_note")>=0)
      {
         ObjectSetInteger(0,name+"_note",OBJPROP_ANCHOR,left_anchor);
         ObjectSetInteger(0,name+"_note",OBJPROP_XDISTANCE,note_start);
      }
      if(ObjectFind(0,name+"_tail")>=0)
      {
         ObjectSetInteger(0,name+"_tail",OBJPROP_ANCHOR,left_anchor);
         int own_unit_width=(ObjectFind(0,name+"_note")>=0 ? (int)ObjectGetInteger(0,name+"_note",OBJPROP_XSIZE) : 0);
         int tail_start=note_start+direction*(own_unit_width+gap);
         if(names[i]=="margin")
            tail_start=annotation_start+direction*24;
         ObjectSetInteger(0,name+"_tail",OBJPROP_XDISTANCE,tail_start);
      }
   }
   {
      int ratio_start=annotation_start;
      // Percent values need a little more room on their right; keep the pips
      // and four-digit rate-difference columns at their existing positions.
      const int ratio_shift=14;
      int ratio_end=ratio_start+direction*(annotation_value_width+ratio_shift);
      for(int i=0;i<6;i++)
      {
         string base=prefix+money_names[i]+"_ratio";
         if(ObjectFind(0,base+"_value")<0) continue;
         ObjectSetInteger(0,base+"_value",OBJPROP_ANCHOR,right_anchor);
         ObjectSetInteger(0,base+"_value",OBJPROP_XDISTANCE,ratio_end);
         ObjectSetInteger(0,base+"_suffix",OBJPROP_ANCHOR,left_anchor);
         ObjectSetInteger(0,base+"_suffix",OBJPROP_XDISTANCE,ratio_end);
      }
      string warning_names[4]={"tp_missing","sl_missing","account_tp_missing","account_sl_missing"};
      for(int i=0;i<4;i++)
      {
         string name=prefix+warning_names[i];
         if(ObjectFind(0,name)<0) continue;
         ObjectSetInteger(0,name,OBJPROP_ANCHOR,left_anchor);
         ObjectSetInteger(0,name,OBJPROP_XDISTANCE,ratio_start);
      }
      int rate_value_end=ratio_end-direction*ratio_shift;
      int widest_rate_text=0;
      for(int i=0;i<2;i++)
      {
         string value_name=prefix+rate_names[i]+"_rate_pips";
         if(ObjectFind(0,value_name)>=0)
            widest_rate_text=(int)MathMax(widest_rate_text,
                                        ObjectGetInteger(0,value_name,OBJPROP_XSIZE));
      }
      // Use empty space inside the four-digit reserve to bring the rightmost
      // values closer to pips; restore the space as the numbers grow.
      int rate_shift=(int)MathMin(24,MathMax(0,rate_pips_width-widest_rate_text-6));
      // Integer-priced symbols need their pips/rate pair closer to the percent
      // column. Keep at least six pixels inside the chart's right edge.
      if(SymbolInfoInteger(_Symbol,SYMBOL_DIGITS)==0)
      {
         int integer_shift=(int)MathMin(14,right ? MathMax(0,InpX+rate_shift-6) : 14);
         rate_value_end+=direction*integer_shift;
      }
      int rate_pips_end=rate_value_end+direction*(rate_middle_width+rate_pips_width-rate_shift);
      for(int i=0;i<2;i++)
      {
         string base=prefix+rate_names[i]+"_rate";
         if(ObjectFind(0,base+"_value")<0) continue;
         ObjectSetInteger(0,base+"_value",OBJPROP_ANCHOR,right_anchor);
         ObjectSetInteger(0,base+"_value",OBJPROP_XDISTANCE,rate_value_end);
         ObjectSetInteger(0,base+"_middle",OBJPROP_ANCHOR,left_anchor);
         ObjectSetInteger(0,base+"_middle",OBJPROP_XDISTANCE,rate_value_end);
         ObjectSetInteger(0,base+"_pips",OBJPROP_ANCHOR,right_anchor);
         ObjectSetInteger(0,base+"_pips",OBJPROP_XDISTANCE,rate_pips_end);
      }
   }
   int header_width=ObjectFind(0,prefix+"header")>=0 ?
                    (int)ObjectGetInteger(0,prefix+"header",OBJPROP_XSIZE) : 0;
   FitBackground((int)MathMax(width,header_width)+(int)MathMax(0,InpX)+20);
}
// Solve a linear price scenario; explicitly reject a flat hedge and negative prices.
bool SolveRate(const double base,const double slope,const double current_value,
               const double target,double &price)
{
   price=EMPTY_VALUE;
   if(MathAbs(slope)<1e-10) return false;
   double result=base+(target-current_value)/slope;
   if(!MathIsValidNumber(result) || result<=0) return false;
   price=result;
   return true;
}
// For a Forex pair whose base is the account currency, convert each position's
// quote-currency P/L at the hypothetical close. Keep the current spread fixed.
// Positive quote P/L buys account currency at Ask; a loss sells it at Bid.
bool FxGrossAt(const double rate,const double spread,const bool ask_basis,
               const double &entries[],const double &quantities[],const bool &buys[],
               const int count,double &gross)
{
   double bid=ask_basis ? rate-spread : rate;
   double ask=bid+spread;
   if(bid<=0 || ask<=0) return false;
   gross=0;
   for(int i=0;i<count;i++)
   {
      double exit_price=buys[i] ? bid : ask;
      double quote_profit=(buys[i] ? exit_price-entries[i] : entries[i]-exit_price)*quantities[i];
      gross+=quote_profit/(quote_profit>=0 ? ask : bid);
   }
   return MathIsValidNumber(gross);
}
// A single-direction Forex book is monotone in price under this model.
bool SolveFxRate(const double base,const double spread,const bool ask_basis,
                 const double &entries[],const double &quantities[],const bool &buys[],
                 const int count,const double target,double &price)
{
   price=EMPTY_VALUE;
   if(count<=0) return false;
   double low=(ask_basis ? spread : 0)+1e-8;
   double high=MathMax(base*2,base+1);
   double at_low,at_high;
   if(!FxGrossAt(low,spread,ask_basis,entries,quantities,buys,count,at_low) ||
      !FxGrossAt(high,spread,ask_basis,entries,quantities,buys,count,at_high)) return false;
   for(int i=0;i<32 && (target<MathMin(at_low,at_high) || target>MathMax(at_low,at_high));i++)
   {
      high*=2;
      if(!FxGrossAt(high,spread,ask_basis,entries,quantities,buys,count,at_high)) return false;
   }
   if(target<MathMin(at_low,at_high) || target>MathMax(at_low,at_high)) return false;
   bool increasing=at_high>at_low;
   for(int i=0;i<48;i++)
   {
      double mid=(low+high)*0.5;
      double at_mid;
      if(!FxGrossAt(mid,spread,ask_basis,entries,quantities,buys,count,at_mid)) return false;
      if((at_mid<target)==increasing) low=mid;
      else high=mid;
   }
   price=(low+high)*0.5;
   return MathIsValidNumber(price) && price>0;
}
void RefreshRates(const int first_row,const double symbol_current_profit)
{
   break_even=EMPTY_VALUE; stop_out=EMPTY_VALUE; margin_level=EMPTY_VALUE;
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double margin=AccountInfoDouble(ACCOUNT_MARGIN);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double free_margin=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double current_profit=AccountInfoDouble(ACCOUNT_PROFIT);
   if(margin>0) margin_level=equity/margin*100.0;
   ResetLastError();
   ENUM_ACCOUNT_STOPOUT_MODE broker_mode=(ENUM_ACCOUNT_STOPOUT_MODE)AccountInfoInteger(ACCOUNT_MARGIN_SO_MODE);
   int mode_error=GetLastError();
   ResetLastError();
   double broker_call=AccountInfoDouble(ACCOUNT_MARGIN_SO_CALL);
   int call_error=GetLastError();
   ResetLastError();
   double broker_stop=AccountInfoDouble(ACCOUNT_MARGIN_SO_SO);
   int stop_error=GetLastError();
   bool mode_valid=mode_error==0 &&
                   (broker_mode==ACCOUNT_STOPOUT_MODE_PERCENT || broker_mode==ACCOUNT_STOPOUT_MODE_MONEY);
   bool broker_percent=broker_mode==ACCOUNT_STOPOUT_MODE_PERCENT;
   bool call_valid=mode_valid && call_error==0 && MathIsValidNumber(broker_call) && broker_call>=0;
   bool broker_stop_valid=mode_valid && stop_error==0 && MathIsValidNumber(broker_stop) && broker_stop>=0;
   bool manual_stop=InpStopOutPercent>0;
   bool stop_valid=manual_stop || broker_stop_valid;
   bool stop_percent=manual_stop || broker_percent;
   double active_stop=manual_stop ? InpStopOutPercent : broker_stop;
   bool call_reached=margin>0 && call_valid &&
                     ThresholdReached(broker_percent,margin_level,equity,broker_call);
   bool margin_warning=margin>0 && margin_level<InpMarginWarningPercent;
   bool stop_reached=margin>0 && stop_valid &&
                     ThresholdReached(stop_percent,margin_level,equity,active_stop);
   if(InpShowRates)
   {
      MqlTick quote={};
      bool quote_ok=SymbolInfoTick(_Symbol,quote) && quote.bid>0 && quote.ask>=quote.bid;
      bool ok=quote_ok;
      int count=0,buys=0,sells=0;
      double slope=0,gross_bid=0,swaps=0,fees=0,current_profit=0;
      int n=PositionsTotal();
      double entries[],quantities[];
      bool directions[];
      ArrayResize(entries,n);
      ArrayResize(quantities,n);
      ArrayResize(directions,n);
      ENUM_SYMBOL_CALC_MODE calc_mode=(ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_CALC_MODE);
      string profit_currency=SymbolInfoString(_Symbol,SYMBOL_CURRENCY_PROFIT);
      bool direct_fx=(calc_mode==SYMBOL_CALC_MODE_FOREX || calc_mode==SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE) &&
                     SymbolInfoString(_Symbol,SYMBOL_CURRENCY_BASE)==account_currency &&
                     profit_currency!=account_currency;
      for(int i=0;i<n;i++)
      {
         if(PositionGetTicket(i)==0) { ok=false; continue; }
         if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
         count++;
         bool buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
         if(buy) buys++; else sells++;
         double contract=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE);
         if(!LinearMode(calc_mode) || contract<=0 ||
            (profit_currency!=account_currency && !direct_fx)) ok=false;
         double lots=PositionGetDouble(POSITION_VOLUME);
         double quantity=lots*contract;
         double direction=(buy ? 1.0 : -1.0);
         double exit_price=(buy ? quote.bid : quote.ask);
         entries[count-1]=PositionGetDouble(POSITION_PRICE_OPEN);
         quantities[count-1]=quantity;
         directions[count-1]=buy;
         gross_bid+=direction*(exit_price-entries[count-1])*quantity;
         slope+=direction*quantity;
         swaps+=PositionGetDouble(POSITION_SWAP);
         current_profit+=PositionGetDouble(POSITION_PROFIT);
         fees+=InpExitCommissionPerLot*lots;
      }
      if(PositionsTotal()!=n) ok=false;
      // Mixed-direction conversion has a more complex P/L curve; keep it unavailable.
      if(direct_fx && buys>0 && sells>0) ok=false;
      bool ask_basis=(sells>0 && buys==0);
      double base=(ask_basis ? quote.ask : quote.bid);
      int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
      string price_text=quote_ok ? Grouped(base,digits) : "取得不可";
      string be_text="",so_text="";
      if(count==0) { be_text+="対象なし"; so_text+="対象なし"; }
      else if(!ok) { be_text+="計算不可"; so_text+="計算不可"; }
      else if(MathAbs(slope)<1e-10)
      {
         be_text+="算出不可: 売買数量が均衡";
         so_text+="算出不可: 売買数量が均衡";
      }
      else
      {
         double fx_gross=0;
         bool fx_ready=!direct_fx || FxGrossAt(base,quote.ask-quote.bid,ask_basis,
                                               entries,quantities,directions,count,fx_gross);
         double net=gross_bid+(InpIncludeSwap ? swaps : 0)-fees;
         bool be_found=direct_fx ?
            (fx_ready && SolveFxRate(base,quote.ask-quote.bid,ask_basis,entries,quantities,
                                     directions,count,fees-(InpIncludeSwap ? swaps : 0),break_even)) :
            SolveRate(base,slope,net,0,break_even);
         if(be_found)
            be_text+=Grouped(break_even,digits)+(direct_fx ? " 概算" : "");
         else be_text+=(fx_ready ? "正の価格に該当なし" : "計算不可");
         if(margin<=0) so_text+="証拠金なし";
         else if(!stop_valid) so_text+="基準取得不可";
         else if(stop_reached) so_text+="強制決済基準以下";
         else
         {
            // Replace only this symbol's sampled floating P/L with the quote-based model.
            // Account equity already includes all accrued swaps; do not add them twice.
            double modeled_equity=equity-current_profit+gross_bid;
            bool so_found=direct_fx ?
               (fx_ready && SolveFxRate(base,quote.ask-quote.bid,ask_basis,entries,quantities,
                                        directions,count,
                                        fx_gross+ThresholdEquity(stop_percent,margin,active_stop)-equity,
                                        stop_out)) :
               SolveRate(base,slope,modeled_equity,
                         ThresholdEquity(stop_percent,margin,active_stop),stop_out);
            if(so_found)
            {
               so_text+=Grouped(stop_out,digits)+(direct_fx ? " 概算" : "");
            }
            else so_text+=(fx_ready ? "正の価格に該当なし" : "計算不可");
         }
      }
      if(!InpCurrentSymbolOnly) { be_text+=" ("+_Symbol+")"; so_text+=" ("+_Symbol+")"; }
      DetailRow("price","現在価格",price_text,first_row,InpInfoColor);
      DetailRow("be","損益分岐",be_text,first_row+1,break_even==EMPTY_VALUE ? InpWarningColor : InpInfoColor);
      DetailRow("so","ロスカット",so_text,first_row+2,InpWarningColor);
      if(break_even!=EMPTY_VALUE) SetRateAnnotation("be",break_even,base,first_row+1,InpInfoColor);
      else DeleteAnnotation("be_rate");
      if(stop_out!=EMPTY_VALUE) SetRateAnnotation("so",stop_out,base,first_row+2,InpWarningColor);
      else DeleteAnnotation("so_rate");
   }
   int profit_row=first_row+(InpShowRates ? 3 : 0);
   if(InpShowCurrentProfit)
   {
      color symbol_colour=symbol_current_profit>0 ? InpCurrentProfitColor :
                           (symbol_current_profit<0 ? InpCurrentLossColor : InpInfoColor);
      DetailRow("symbol_profit","現在損益(銘柄)",
                Money(symbol_current_profit,account_currency,InpDecimals),profit_row,symbol_colour);
      SetRatioAnnotation("symbol_profit",symbol_current_profit,balance,profit_row,symbol_colour);
      color profit_colour=current_profit>0 ? InpCurrentProfitColor :
                           (current_profit<0 ? InpCurrentLossColor : InpInfoColor);
      DetailRow("current_profit","現在損益(口座)",
                Money(current_profit,account_currency,InpDecimals),profit_row+1,profit_colour);
      SetRatioAnnotation("current_profit",current_profit,balance,profit_row+1,profit_colour);
   }
   int account_row=profit_row+(InpShowCurrentProfit ? 2 : 0);
   if(InpShowAccountDetails)
   {
      DetailRow("balance","残高",(balance<0 ? "-" : "")+Grouped(balance,InpDecimals)+" "+account_currency,account_row,InpInfoColor);
      DetailRow("equity","有効証拠金",(equity<0 ? "-" : "")+Grouped(equity,InpDecimals)+" "+account_currency,account_row+1,InpInfoColor);
      DetailRow("used_margin","必要証拠金",(margin<0 ? "-" : "")+Grouped(margin,InpDecimals)+" "+account_currency,account_row+2,InpInfoColor);
      DetailRow("free_margin","余剰証拠金",(free_margin<0 ? "-" : "")+Grouped(free_margin,InpDecimals)+" "+account_currency,account_row+3,InpInfoColor);
   }
   if(InpShowMarginLevel)
   {
      string text=(margin>0 ? Grouped(margin_level,2)+"%" : "対象なし");
      text+=" ストップアウト "+(stop_valid ? ThresholdText(active_stop,stop_percent,account_currency) : "取得不可");
      if(manual_stop) text+=" 手動";
      color margin_colour=call_reached ? InpMarginCallColor :
                          (margin_warning ? InpMarginWarningColor : InpInfoColor);
      DetailRow("margin","証拠金維持率",text,account_row+(InpShowAccountDetails ? 4 : 0),margin_colour);
   }
   uint now=GetTickCount();
   if(!monitor_hidden && layout_dirty && (last_layout_tick==0 || now-last_layout_tick>=100))
   {
      if(!layout_measure_requested)
      {
         // Let MT5 paint updated text before reading OBJPROP_XSIZE.
         ChartRedraw(0);
         layout_measure_requested=true;
      }
      else if(LabelWidthsReady())
      {
         AlignDetailRows();
         layout_dirty=false;
         if(!layout_visible)
         {
            layout_visible=true;
            ChartRedraw(0);
            Print("Position Monitor layout ready");
         }
      }
      last_layout_tick=now;
   }
}
void Refresh()
{
   total_tp=0; total_sl=0; total_positions=0;
   account_tp=0; account_sl=0; account_positions=0;
   double total_lots=0;
   double symbol_current_profit=0;
   int missing_tp=0,missing_sl=0,error_tp=0,error_sl=0;
   int account_missing_tp=0,account_missing_sl=0,account_error_tp=0,account_error_sl=0;
   bool snapshot_failed=false;
   int n=PositionsTotal();
   for(int i=0;i<n;i++)
   {
      if(PositionGetTicket(i)==0) { snapshot_failed=true; continue; }
      string symbol=PositionGetString(POSITION_SYMBOL);
      bool selected=!InpCurrentSymbolOnly || symbol==_Symbol;
      if(symbol==_Symbol) symbol_current_profit+=PositionGetDouble(POSITION_PROFIT);
      account_positions++;
      if(!selected && !InpShowAccountTotals) continue;
      if(selected) total_positions++;
      bool buy=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
      double lots=PositionGetDouble(POSITION_VOLUME);
      if(selected) total_lots+=lots;
      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double tp=PositionGetDouble(POSITION_TP),sl=PositionGetDouble(POSITION_SL);
      double costs=(InpIncludeSwap ? PositionGetDouble(POSITION_SWAP) : 0)
                   -InpExitCommissionPerLot*lots;
      double result;
      if(tp<=0)
      {
         account_missing_tp++;
         if(selected) missing_tp++;
      }
      else if(Estimate(symbol,buy,lots,entry,tp,result))
      {
         account_tp+=result+costs;
         if(selected) total_tp+=result+costs;
      }
      else
      {
         account_error_tp++;
         if(selected) error_tp++;
      }
      if(sl<=0)
      {
         account_missing_sl++;
         if(selected) missing_sl++;
      }
      else if(Estimate(symbol,buy,lots,entry,sl,result))
      {
         account_sl+=result+costs;
         if(selected) total_sl+=result+costs;
      }
      else
      {
         account_error_sl++;
         if(selected) error_sl++;
      }
   }
   if(PositionsTotal()!=n) snapshot_failed=true;
   if(snapshot_failed)
   {
      error_tp++; error_sl++;
      account_error_tp++; account_error_sl++;
   }
   valid_tp=(error_tp==0 && missing_tp==0);
   valid_sl=(error_sl==0 && missing_sl==0);
   valid_account_tp=(account_error_tp==0 && account_missing_tp==0);
   valid_account_sl=(account_error_sl==0 && account_missing_sl==0);
   if(InpShowHeader)
   {
      string header=(InpCurrentSymbolOnly ? _Symbol : "全銘柄")+" | "+
                    IntegerToString(total_positions)+" ポジション | "+LotsText(total_lots)+" ロット";
      if(snapshot_failed) header+=" [取得不完全]";
      if(InpExitCommissionPerLot>0) header+=" | 決済手数料控除";
      PutLabel("header",header,0,InpInfoColor,InpFontSize);
   }
   int offset=InpShowHeader ? 1 : 0;
   MoneyRows(offset,missing_tp,error_tp,missing_sl,error_sl,
             account_missing_tp,account_error_tp,account_missing_sl,account_error_sl);
   RefreshRates(offset+2+(InpCurrentSymbolOnly && InpShowAccountTotals ? 2 : 0),
                symbol_current_profit);
   PublishBuffers();
}
bool SelfTest()
{
   string numeric,unit;
   SplitNumber("+18,813.00 USD",numeric,unit);
   if(numeric!="+18,813.00" || unit!="USD") return false;
   SplitNumber("207.70% ストップアウト 20%",numeric,unit);
   if(numeric!="207.70" || unit!="% ストップアウト 20%") return false;
   SplitNumber("80,899.31",numeric,unit);
   if(numeric!="80,899.31" || unit!="") return false;
   if(LotsText(10.0)!="10" || LotsText(0.001)!="0.001" ||
      LotsText(1000.125)!="1,000.125") return false;
   string ratio;
   if(!RatioValue(22359,4984.95,ratio) || ratio!="+448.53" ||
      !RatioValue(-4229,4984.95,ratio) || ratio!="-84.84" ||
      RatioValue(100,0,ratio)) return false;
   if(SignedGrouped(123.4,1)!="+123.4" || SignedGrouped(-0.25,2)!="-0.25" ||
      SignedGrouped(0,1)!="0.0") return false;
   if(ThresholdText(100,true,"USD")!="100%" ||
      ThresholdText(20.5,true,"USD")!="20.5%" ||
      ThresholdText(500,false,"USD")!="500 USD") return false;
   if(!ThresholdReached(true,100,9000,100) || ThresholdReached(true,100.01,0,100)) return false;
   if(!ThresholdReached(false,200,500,500) || ThresholdReached(false,0,500.01,500)) return false;
   if(MathAbs(ThresholdEquity(true,4000,20)-800)>1e-8 ||
      MathAbs(ThresholdEquity(false,4000,500)-500)>1e-8) return false;
   double rate;
   if(!SolveRate(80000,-10,4813,0,rate) || MathAbs(rate-80481.3)>1e-7) return false;
   if(!SolveRate(80000,-10,9797.95,804.814,rate) || MathAbs(rate-80899.3136)>1e-7) return false;
   if(!SolveRate(100,2,20,0,rate) || MathAbs(rate-90)>1e-7) return false;
   if(SolveRate(100,0,20,0,rate)) return false;
   if(SolveRate(100,1,200,0,rate)) return false;
   double fx_entries[1]={150.0},fx_quantities[1]={100000.0};
   bool fx_buys[1]={true};
   double fx_gross;
   if(!FxGrossAt(150.0,0.006,false,fx_entries,fx_quantities,fx_buys,1,fx_gross) ||
      MathAbs(fx_gross)>1e-8) return false;
   if(!SolveFxRate(149.0,0.006,false,fx_entries,fx_quantities,fx_buys,1,0,rate) ||
      MathAbs(rate-150.0)>1e-7) return false;
   if(!FxGrossAt(151.0,0.006,false,fx_entries,fx_quantities,fx_buys,1,fx_gross) ||
      MathAbs(fx_gross-100000.0/151.006)>1e-7) return false;
   if(!SolveFxRate(149.0,0.006,false,fx_entries,fx_quantities,fx_buys,1,fx_gross,rate) ||
      MathAbs(rate-151.0)>1e-7) return false;
   fx_buys[0]=false;
   if(!FxGrossAt(149.0,0.006,true,fx_entries,fx_quantities,fx_buys,1,fx_gross) ||
      MathAbs(fx_gross-100000.0/149.0)>1e-7) return false;
   if(!SolveFxRate(150.0,0.006,true,fx_entries,fx_quantities,fx_buys,1,fx_gross,rate) ||
      MathAbs(rate-149.0)>1e-7) return false;
   string tp_text=PadAmount(Money(18813,"USD",2),20);
   string sl_text=PadAmount(Money(-2187,"USD",2),20);
   if(StringLen(tp_text)!=20 || StringLen(sl_text)!=20 ||
      StringFind(tp_text,",")!=StringFind(sl_text,",") ||
      StringFind(tp_text,".")!=StringFind(sl_text,".")) return false;
   return Grouped(18813,2)=="18,813.00" &&
          Money(-2187,"USD",2)=="-2,187.00 USD" &&
          Grouped(999.999,2)=="1,000.00" &&
          Grouped(1234567.89,2)=="1,234,567.89" &&
          Money(-0.001,"USD",2)=="0.00 USD";
}
int OnInit()
{
   if(InpFontSize<8 || InpFontSize>72 || InpDecimals<0 || InpDecimals>8 ||
      InpRowSpacing<0 || InpExitCommissionPerLot<0 || InpStopOutPercent<0 ||
      InpMarginWarningPercent<=0 || InpTrialTP<0 || InpTrialSL<0 ||
      InpScenarioX<0 || InpScenarioY<0 || !SelfTest() || !ScenarioSelfTest())
      return INIT_PARAMETERS_INCORRECT;
   SetIndexBuffer(0,TPBuffer,INDICATOR_DATA);
   SetIndexBuffer(1,SLBuffer,INDICATOR_DATA);
   SetIndexBuffer(2,BEBuffer,INDICATOR_DATA);
   SetIndexBuffer(3,SOBuffer,INDICATOR_DATA);
   SetIndexBuffer(4,MarginBuffer,INDICATOR_DATA);
   ArraySetAsSeries(TPBuffer,true);
   ArraySetAsSeries(SLBuffer,true);
   ArraySetAsSeries(BEBuffer,true);
   ArraySetAsSeries(SOBuffer,true);
   ArraySetAsSeries(MarginBuffer,true);
   PlotIndexSetDouble(0,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetDouble(1,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetDouble(2,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetDouble(3,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetDouble(4,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   IndicatorSetInteger(INDICATOR_DIGITS,InpDecimals);
   account_currency=AccountInfoString(ACCOUNT_CURRENCY);
   prefix="PositionMonitor_"+IntegerToString(ChartID())+"_";
   ObjectsDeleteAll(0,prefix);
   ObjectsDeleteAll(0,ScenarioPrefix());
   last_layout_tick=0;
   layout_dirty=true;
   layout_visible=false;
   layout_measure_requested=false;
   monitor_hidden=false;
   scenario_hidden=(InpTrialTP<=0 && InpTrialSL<=0);
   scenario_position_key="";
   last_scenario_check=0;
   max_background_width=0;
   CreateBackground();
   CreateToggleButton("monitor",95);
   CreateToggleButton("scenario",181);
   SetToggleText("scenario",scenario_hidden);
   CreateFourDigitWidthSamples();
   if(!EventSetMillisecondTimer(100)) return INIT_FAILED;
   Refresh();
   if(!scenario_hidden)
   {
      ScenarioRun();
      scenario_position_key=ScenarioPositionKey();
   }
   PrintFormat("Read-only initialized. Positions=%d TP=%s SL=%s SelfTest=PASS",
               total_positions,valid_tp ? Money(total_tp,account_currency,InpDecimals) : "incomplete",
               valid_sl ? Money(total_sl,account_currency,InpDecimals) : "incomplete");
   PrintFormat("Account TP/SL totals. Positions=%d TP=%s SL=%s",
               account_positions,
               valid_account_tp ? Money(account_tp,account_currency,InpDecimals) : "incomplete",
               valid_account_sl ? Money(account_sl,account_currency,InpDecimals) : "incomplete");
   PrintFormat("Margin thresholds. Mode=%d Call=%.4f StopOut=%.4f Override=%.4f",
               (int)AccountInfoInteger(ACCOUNT_MARGIN_SO_MODE),
               AccountInfoDouble(ACCOUNT_MARGIN_SO_CALL),AccountInfoDouble(ACCOUNT_MARGIN_SO_SO),
               InpStopOutPercent);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(prefix!="")
   {
      int buttons=ObjectsDeleteAll(0,prefix+"toggle_",0,OBJ_BUTTON);
      int scenario_objects=ObjectsDeleteAll(0,ScenarioPrefix());
      int monitor_objects=ObjectsDeleteAll(0,prefix);
      PrintFormat("PositionMonitor cleanup: reason=%d buttons=%d scenario=%d monitor=%d",
                  reason,buttons,scenario_objects,monitor_objects);
   }
   ChartRedraw(0);
}
void OnTimer()
{
   Refresh();
   if(!scenario_hidden)
   {
      uint now=GetTickCount();
      if(last_scenario_check==0 || now-last_scenario_check>=1000)
      {
         last_scenario_check=now;
         string current_key=ScenarioPositionKey();
         if(current_key=="unavailable") return;
         if(current_key!=scenario_position_key ||
            (ObjectFind(0,ScenarioPrefix()+"background")<0 &&
             ObjectFind(0,ScenarioPrefix()+"message")<0))
         {
            ScenarioRun();
            scenario_position_key=current_key;
         }
         else ScenarioRefreshCurrent();
      }
   }
}
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id!=CHARTEVENT_OBJECT_CLICK) return;
   if(sparam==prefix+"toggle_monitor")
   {
      monitor_hidden=!monitor_hidden;
      SetPanelVisibility(prefix,monitor_hidden);
      SetToggleText("monitor",monitor_hidden);
      if(!monitor_hidden)
      {
         layout_dirty=true;
         layout_measure_requested=false;
      }
   }
   else if(sparam==prefix+"toggle_scenario")
   {
      scenario_hidden=!scenario_hidden;
      if(scenario_hidden) SetPanelVisibility(ScenarioPrefix(),true);
      else
      {
         ScenarioRun();
         scenario_position_key=ScenarioPositionKey();
         last_scenario_check=GetTickCount();
      }
      SetToggleText("scenario",scenario_hidden);
   }
   else return;
   ChartRedraw(0);
}
int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
{
   if(prev_calculated==0)
   {
      ArrayInitialize(TPBuffer,EMPTY_VALUE);
      ArrayInitialize(SLBuffer,EMPTY_VALUE);
      ArrayInitialize(BEBuffer,EMPTY_VALUE);
      ArrayInitialize(SOBuffer,EMPTY_VALUE);
      ArrayInitialize(MarginBuffer,EMPTY_VALUE);
   }
   return rates_total;
}
