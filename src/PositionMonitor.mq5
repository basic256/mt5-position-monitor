// Read-only TP/SL totals. No trading functions, DLLs, network or advertisements.
#property version   "1.37"
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
input bool InpIncludeSwap=true;              // 現在までのスワップを含める
input double InpExitCommissionPerLot=0.0;    // 決済時の手数料/lot（口座通貨・片道）
input ENUM_BASE_CORNER InpCorner=CORNER_LEFT_LOWER; // 表示する隅
input int InpX=15;                          // 左右端からの距離 px
input int InpY=25;                          // 上下端からの距離 px
input int InpFontSize=11;                   // 損益の文字サイズ
input int InpRowSpacing=0;                  // 行間 px（0=文字サイズに合わせて自動）
input string InpFont="Meiryo";              // フォント
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

double TPBuffer[],SLBuffer[];
double BEBuffer[],SOBuffer[],MarginBuffer[];
double break_even=EMPTY_VALUE,stop_out=EMPTY_VALUE,margin_level=EMPTY_VALUE;
string prefix;
double total_tp=0,total_sl=0;
bool valid_tp=true,valid_sl=true;
int total_positions=0;
string account_currency;
uint last_layout_tick=0;
bool layout_dirty=true;
bool layout_visible=false;
bool layout_measure_requested=false;

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
   int rows=(InpShowHeader ? 3 : 2)+(InpShowRates ? 3 : 0)
            +(InpShowCurrentProfit ? 1 : 0)+(InpShowAccountDetails ? 4 : 0)
            +(InpShowMarginLevel ? 1 : 0);
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
      ObjectSetString(0,name,OBJPROP_FONT,InpFont);
   }
   if(created || ObjectGetInteger(0,name,OBJPROP_COLOR)!=(long)colour)
      ObjectSetInteger(0,name,OBJPROP_COLOR,colour);
   if(!created)
   {
      string previous_text=ObjectGetString(0,name,OBJPROP_TEXT);
      if(previous_text!=text)
      {
         if(StringLen(previous_text)!=StringLen(text)) layout_dirty=true;
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
   if(suffix=="current_profit") tip="口座全体の現在の含み損益。MT5のACCOUNT_PROFITと、現在の口座残高に対する増減率を表示します。";
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
string RowText(const string title,const double value,const int missing,const int errors)
{
   if(errors>0) return title+"  計算不可 ("+IntegerToString(errors)+"件)";
   string text=title+"  "+Money(value,account_currency,InpDecimals);
   if(InpShowJPY && total_positions>0)
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
   if(missing>0) text+=" [未設定 "+IntegerToString(missing)+"件・一部合計]";
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
void SetRateAnnotation(const string suffix,const double target,const double current,
                       const int row,const color colour)
{
   string rate_difference,pips;
   if(!RateDifferenceValues(target,current,rate_difference,pips)) { DeleteAnnotation(suffix+"_rate"); return; }
   string base=suffix+"_rate";
   PutLabel(base+"_value",pips,row,colour,InpFontSize);
   PutLabel(base+"_middle"," pips   ",row,colour,InpFontSize);
   PutLabel(base+"_pips",rate_difference,row,colour,InpFontSize);
   string tip=ObjectGetString(0,prefix+suffix,OBJPROP_TOOLTIP);
   string parts[3]={"_value","_middle","_pips"};
   for(int i=0;i<3;i++) ObjectSetString(0,prefix+base+parts[i],OBJPROP_TOOLTIP,tip);
}
void MoneyRows(const int first_row,const int missing_tp,const int error_tp,
               const int missing_sl,const int error_sl)
{
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   color tp_color=!valid_tp ? InpWarningColor : (total_tp<0 ? InpLossColor : InpProfitColor);
   color sl_color=!valid_sl ? InpWarningColor : (total_sl<0 ? InpLossColor : InpProfitColor);
   RenderValueRow("tp","TP合計",StringSubstr(RowText("",total_tp,missing_tp,error_tp),2),first_row,tp_color);
   RenderValueRow("sl","SL合計",StringSubstr(RowText("",total_sl,missing_sl,error_sl),2),first_row+1,sl_color);
   if(error_tp==0) SetRatioAnnotation("tp",total_tp,balance,first_row,tp_color);
   else DeleteAnnotation("tp_ratio");
   if(error_sl==0) SetRatioAnnotation("sl",total_sl,balance,first_row+1,sl_color);
   else DeleteAnnotation("sl_ratio");
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
void AlignDetailRows()
{
   string names[11]={"tp","sl","price","be","so","current_profit","balance","equity","used_margin","free_margin","margin"};
   string money_names[3]={"tp","sl","current_profit"};
   string rate_names[2]={"be","so"};
   int title_width=0,value_width=0,unit_width=0,tail_width=0,money_unit_width=0;
   int ratio_value_width=0,ratio_suffix_width=0;
   int rate_value_width=0,rate_middle_width=0,rate_pips_width=0;
   for(int i=0;i<11;i++)
   {
      string name=prefix+names[i];
      if(ObjectFind(0,name)<0) continue;
      title_width=(int)MathMax(title_width,ObjectGetInteger(0,name,OBJPROP_XSIZE));
      value_width=(int)MathMax(value_width,ObjectGetInteger(0,name+"_value",OBJPROP_XSIZE));
      if(ObjectFind(0,name+"_note")>=0)
         unit_width=(int)MathMax(unit_width,ObjectGetInteger(0,name+"_note",OBJPROP_XSIZE));
      if(ObjectFind(0,name+"_tail")>=0)
         tail_width=(int)MathMax(tail_width,ObjectGetInteger(0,name+"_tail",OBJPROP_XSIZE));
   }
   for(int i=0;i<3;i++)
   {
      string name=prefix+money_names[i];
      if(ObjectFind(0,name+"_note")>=0)
         money_unit_width=(int)MathMax(money_unit_width,ObjectGetInteger(0,name+"_note",OBJPROP_XSIZE));
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
   int generic_width=unit_width+(tail_width>0 ? gap+tail_width : 0);
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
   int numeric_end=origin+(right ? -1 : 1)*(title_width+gap+value_width);
   int note_start=numeric_end+(right ? -gap : gap);
   int direction=(right ? -1 : 1);
   if(ObjectFind(0,prefix+"header")>=0)
      ObjectSetInteger(0,prefix+"header",OBJPROP_XDISTANCE,(int)MathMax(0,InpX));
   for(int i=0;i<11;i++)
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
            tail_start=note_start+direction*(money_unit_width+gap);
         ObjectSetInteger(0,name+"_tail",OBJPROP_XDISTANCE,tail_start);
      }
   }
   {
      int ratio_start=note_start+direction*(money_unit_width+gap);
      int ratio_end=ratio_start+direction*annotation_value_width;
      for(int i=0;i<3;i++)
      {
         string base=prefix+money_names[i]+"_ratio";
         if(ObjectFind(0,base+"_value")<0) continue;
         ObjectSetInteger(0,base+"_value",OBJPROP_ANCHOR,right_anchor);
         ObjectSetInteger(0,base+"_value",OBJPROP_XDISTANCE,ratio_end);
         ObjectSetInteger(0,base+"_suffix",OBJPROP_ANCHOR,left_anchor);
         ObjectSetInteger(0,base+"_suffix",OBJPROP_XDISTANCE,ratio_end);
      }
      int rate_value_end=ratio_end;
      int rate_pips_end=rate_value_end+direction*(rate_middle_width+rate_pips_width);
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
void RefreshRates(const int first_row)
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
      for(int i=0;i<n;i++)
      {
         if(PositionGetTicket(i)==0) { ok=false; continue; }
         if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
         count++;
         bool buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
         if(buy) buys++; else sells++;
         double contract=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE);
         ENUM_SYMBOL_CALC_MODE mode=(ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_CALC_MODE);
         // This root solver is exact only for fixed-conversion linear contracts.
         // Unsupported/nonlinear contracts are shown as unavailable, never a guessed rate.
         if(!LinearMode(mode) || contract<=0 ||
            SymbolInfoString(_Symbol,SYMBOL_CURRENCY_PROFIT)!=account_currency) ok=false;
         double lots=PositionGetDouble(POSITION_VOLUME);
         double quantity=lots*contract;
         double direction=(buy ? 1.0 : -1.0);
         double exit_price=(buy ? quote.bid : quote.ask);
         gross_bid+=direction*(exit_price-PositionGetDouble(POSITION_PRICE_OPEN))*quantity;
         slope+=direction*quantity;
         swaps+=PositionGetDouble(POSITION_SWAP);
         current_profit+=PositionGetDouble(POSITION_PROFIT);
         fees+=InpExitCommissionPerLot*lots;
      }
      if(PositionsTotal()!=n) ok=false;
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
         double net=gross_bid+(InpIncludeSwap ? swaps : 0)-fees;
         if(SolveRate(base,slope,net,0,break_even))
            be_text+=Grouped(break_even,digits);
         else be_text+="正の価格に該当なし";
         if(margin<=0) so_text+="証拠金なし";
         else if(!stop_valid) so_text+="基準取得不可";
         else if(stop_reached) so_text+="強制決済基準以下";
         else
         {
            // Replace only this symbol's sampled floating P/L with the quote-based model.
            // Account equity already includes all accrued swaps; do not add them twice.
            double modeled_equity=equity-current_profit+gross_bid;
            if(SolveRate(base,slope,modeled_equity,
                         ThresholdEquity(stop_percent,margin,active_stop),stop_out))
            {
               so_text+=Grouped(stop_out,digits);
            }
            else so_text+="正の価格に該当なし";
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
      color profit_colour=current_profit>0 ? InpCurrentProfitColor :
                           (current_profit<0 ? InpCurrentLossColor : InpInfoColor);
      DetailRow("current_profit","現在損益",Money(current_profit,account_currency,InpDecimals),profit_row,profit_colour);
      SetRatioAnnotation("current_profit",current_profit,balance,profit_row,profit_colour);
   }
   int account_row=profit_row+(InpShowCurrentProfit ? 1 : 0);
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
      DetailRow("margin","維持率",text,account_row+(InpShowAccountDetails ? 4 : 0),margin_colour);
   }
   uint now=GetTickCount();
   if(layout_dirty && (last_layout_tick==0 || now-last_layout_tick>=100))
   {
      if(LabelWidthsReady())
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
      else if(!layout_measure_requested)
      {
         // One paint while labels are off-screen provides their real pixel widths.
         ChartRedraw(0);
         layout_measure_requested=true;
      }
      last_layout_tick=now;
   }
}
void Refresh()
{
   total_tp=0; total_sl=0; total_positions=0;
   double total_lots=0;
   int missing_tp=0,missing_sl=0,error_tp=0,error_sl=0;
   bool snapshot_failed=false;
   int n=PositionsTotal();
   for(int i=0;i<n;i++)
   {
      if(PositionGetTicket(i)==0) { snapshot_failed=true; continue; }
      string symbol=PositionGetString(POSITION_SYMBOL);
      if(InpCurrentSymbolOnly && symbol!=_Symbol) continue;
      total_positions++;
      bool buy=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
      double lots=PositionGetDouble(POSITION_VOLUME);
      total_lots+=lots;
      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double tp=PositionGetDouble(POSITION_TP),sl=PositionGetDouble(POSITION_SL);
      double costs=(InpIncludeSwap ? PositionGetDouble(POSITION_SWAP) : 0)
                   -InpExitCommissionPerLot*lots;
      double result;
      if(tp<=0) missing_tp++;
      else if(Estimate(symbol,buy,lots,entry,tp,result)) total_tp+=result+costs;
      else error_tp++;
      if(sl<=0) missing_sl++;
      else if(Estimate(symbol,buy,lots,entry,sl,result)) total_sl+=result+costs;
      else error_sl++;
   }
   if(PositionsTotal()!=n) snapshot_failed=true;
   if(snapshot_failed) { error_tp++; error_sl++; }
   valid_tp=(error_tp==0 && missing_tp==0);
   valid_sl=(error_sl==0 && missing_sl==0);
   if(InpShowHeader)
   {
      string header=(InpCurrentSymbolOnly ? _Symbol : "全銘柄")+" | "+
                    IntegerToString(total_positions)+" ポジション | "+LotsText(total_lots)+" ロット";
      if(snapshot_failed) header+=" [取得不完全]";
      if(InpExitCommissionPerLot>0) header+=" | 決済手数料控除";
      PutLabel("header",header,0,InpInfoColor,InpFontSize);
   }
   int offset=InpShowHeader ? 1 : 0;
   MoneyRows(offset,missing_tp,error_tp,missing_sl,error_sl);
   RefreshRates(offset+2);
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
      InpMarginWarningPercent<=0 || !SelfTest())
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
   last_layout_tick=0;
   layout_dirty=true;
   layout_visible=false;
   layout_measure_requested=false;
   CreateFourDigitWidthSamples();
   if(!EventSetMillisecondTimer(100)) return INIT_FAILED;
   Refresh();
   PrintFormat("Read-only initialized. Positions=%d TP=%s SL=%s SelfTest=PASS",
               total_positions,valid_tp ? Money(total_tp,account_currency,InpDecimals) : "incomplete",
               valid_sl ? Money(total_sl,account_currency,InpDecimals) : "incomplete");
   PrintFormat("Margin thresholds. Mode=%d Call=%.4f StopOut=%.4f Override=%.4f",
               (int)AccountInfoInteger(ACCOUNT_MARGIN_SO_MODE),
               AccountInfoDouble(ACCOUNT_MARGIN_SO_CALL),AccountInfoDouble(ACCOUNT_MARGIN_SO_SO),
               InpStopOutPercent);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(prefix!="") ObjectsDeleteAll(0,prefix);
   ChartRedraw(0);
}
void OnTimer() { Refresh(); }
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
