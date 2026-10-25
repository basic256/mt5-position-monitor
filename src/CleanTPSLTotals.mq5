// Read-only TP/SL totals. No trading functions, DLLs, network or advertisements.
#property version   "1.10"
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
input int InpFontSize=14;                   // 損益の文字サイズ
input int InpRowSpacing=28;                 // 行間 px
input string InpFont="Meiryo";              // フォント
input int InpDecimals=2;                    // 小数点以下の桁数
input bool InpShowHeader=true;              // 銘柄・件数・スワップ設定
input bool InpShowJPY=false;                // 円換算も表示（気配値に換算銘柄が必要）
input bool InpShowRates=true;              // 現在チャート銘柄の損益分岐・ロスカット目安
input double InpStopOutPercent=20.0;        // ロスカットの証拠金維持率 %（ThreeTrader:20）
input bool InpShowMarginLevel=true;         // 現在の口座証拠金維持率
input color InpProfitColor=clrLimeGreen;    // 利益の色
input color InpLossColor=clrTomato;         // 損失の色
input color InpInfoColor=clrSilver;         // 補助文字の色
input color InpWarningColor=clrOrange;      // 未設定・計算不可の色

double TPBuffer[],SLBuffer[];
double BEBuffer[],SOBuffer[],MarginBuffer[];
double break_even=EMPTY_VALUE,stop_out=EMPTY_VALUE,margin_level=EMPTY_VALUE;
string prefix;
double total_tp=0,total_sl=0;
bool valid_tp=true,valid_sl=true;
int total_positions=0;
string account_currency;

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
string Money(const double value,const string currency,const int digits)
{
   double rounded=NormalizeDouble(value,digits);
   return (rounded<0 ? "-" : (rounded>0 ? "+" : ""))+Grouped(rounded,digits)+" "+currency;
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
   if(ObjectFind(0,name)<0 && !ObjectCreate(0,name,OBJ_LABEL,0,0,0)) return false;
   bool bottom=(InpCorner==CORNER_LEFT_LOWER || InpCorner==CORNER_RIGHT_LOWER);
   bool right=(InpCorner==CORNER_RIGHT_UPPER || InpCorner==CORNER_RIGHT_LOWER);
   ENUM_ANCHOR_POINT anchor=bottom ? (right ? ANCHOR_RIGHT_LOWER : ANCHOR_LEFT_LOWER)
                                   : (right ? ANCHOR_RIGHT_UPPER : ANCHOR_LEFT_UPPER);
   int spacing=(int)MathMax(InpRowSpacing,InpFontSize*2);
   int rows=(InpShowHeader ? 3 : 2)+(InpShowRates ? 2 : 0)+(InpShowMarginLevel ? 1 : 0);
   int distance=(int)MathMax(0,InpY)+(bottom ? rows-1-row : row)*spacing;
   ObjectSetInteger(0,name,OBJPROP_CORNER,InpCorner);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,anchor);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,(int)MathMax(0,InpX));
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,distance);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,size);
   ObjectSetInteger(0,name,OBJPROP_COLOR,colour);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetString(0,name,OBJPROP_FONT,InpFont);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   string tip="設定価格での決済見積り。予約注文・滑り・将来Swap・支払済み手数料は含みません。";
   if(suffix=="so") tip="最初の強制決済の推定開始価格。現在の必要証拠金・他銘柄損益・為替・スプレッドを固定し、途中のSL/TP決済を無視した仮定です。全件決済価格ではありません。";
   if(suffix=="be") tip="現在チャート銘柄の合計損益がゼロになる決済価格。Swap設定と入力済み決済手数料を反映。両建てでは現在スプレッドを固定したBid換算。";
   ObjectSetString(0,name,OBJPROP_TOOLTIP,tip);
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
void PublishBuffers()
{
   if(ArraySize(TPBuffer)>0) TPBuffer[0]=valid_tp ? total_tp : EMPTY_VALUE;
   if(ArraySize(SLBuffer)>0) SLBuffer[0]=valid_sl ? total_sl : EMPTY_VALUE;
   if(ArraySize(BEBuffer)>0) BEBuffer[0]=break_even;
   if(ArraySize(SOBuffer)>0) SOBuffer[0]=stop_out;
   if(ArraySize(MarginBuffer)>0) MarginBuffer[0]=margin_level;
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
   double margin=AccountInfoDouble(ACCOUNT_MARGIN);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(margin>0) margin_level=equity/margin*100.0;
   if(InpShowRates)
   {
      MqlTick quote={};
      bool ok=SymbolInfoTick(_Symbol,quote) && quote.bid>0 && quote.ask>=quote.bid;
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
      string basis=(ask_basis ? "Ask" : "Bid");
      string be_text="損益分岐  ",so_text="ロスカット目安 ("+DoubleToString(InpStopOutPercent,1)+"%)  ";
      if(count==0) { be_text+="対象なし"; so_text+="対象なし"; }
      else if(!ok) { be_text+="計算不可"; so_text+="計算不可"; }
      else if(MathAbs(slope)<1e-10)
      {
         be_text+="算出不可（売買数量が均衡）";
         so_text+="算出不可（売買数量が均衡）";
      }
      else
      {
         double net=gross_bid+(InpIncludeSwap ? swaps : 0)-fees;
         if(SolveRate(base,slope,net,0,break_even))
            be_text+=Grouped(break_even,(int)MathMax(2,SymbolInfoInteger(_Symbol,SYMBOL_DIGITS)))+" "+basis;
         else be_text+="正の価格に該当なし";
         if(margin<=0) so_text+="証拠金なし";
         else if(margin_level<=InpStopOutPercent) so_text+="維持率が基準以下";
         else
         {
            // Replace only this symbol's sampled floating P/L with the quote-based model.
            // Account equity already includes all accrued swaps; do not add them twice.
            double modeled_equity=equity-current_profit+gross_bid;
            if(SolveRate(base,slope,modeled_equity,margin*InpStopOutPercent/100.0,stop_out))
            {
               so_text+=Grouped(stop_out,(int)MathMax(2,SymbolInfoInteger(_Symbol,SYMBOL_DIGITS)))+" "+basis+" [証拠金固定]";
               bool prior_exit=false;
               for(int j=0;j<PositionsTotal();j++)
               {
                  if(PositionGetTicket(j)==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
                  bool buy=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
                  double shift=(!buy && !ask_basis ? quote.ask-quote.bid : 0);
                  double sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
                  if(sl>0) { sl-=shift; if((sl-base)*(sl-stop_out)<0) prior_exit=true; }
                  if(tp>0) { tp-=shift; if((tp-base)*(tp-stop_out)<0) prior_exit=true; }
               }
               if(prior_exit) so_text+=" [SL/TP先行]";
            }
            else so_text+="正の価格に該当なし";
         }
      }
      if(!InpCurrentSymbolOnly) { be_text+=" ("+_Symbol+")"; so_text+=" ("+_Symbol+")"; }
      PutLabel("be",be_text,first_row,break_even==EMPTY_VALUE ? InpWarningColor : InpInfoColor,InpFontSize);
      PutLabel("so",so_text,first_row+1,InpWarningColor,InpFontSize);
   }
   if(InpShowMarginLevel)
   {
      string text="証拠金維持率  "+(margin>0 ? Grouped(margin_level,1)+"%" : "対象なし");
      text+=" / ロスカット基準 "+DoubleToString(InpStopOutPercent,1)+"%";
      PutLabel("margin",text,first_row+(InpShowRates ? 2 : 0),InpInfoColor,InpFontSize);
   }
}
void Refresh()
{
   total_tp=0; total_sl=0; total_positions=0;
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
      string header=(InpCurrentSymbolOnly ? _Symbol : "全銘柄")+" | "+IntegerToString(total_positions)+"件";
      header+=(InpIncludeSwap ? " | 現在Swap込み" : " | Swap除外");
      if(InpExitCommissionPerLot>0) header+=" | 決済手数料控除";
      PutLabel("header",header,0,InpInfoColor,(int)MathMax(8,InpFontSize-3));
   }
   int offset=InpShowHeader ? 1 : 0;
   PutLabel("tp",RowText("TP合計",total_tp,missing_tp,error_tp),offset,
            !valid_tp ? InpWarningColor : (total_tp<0 ? InpLossColor : InpProfitColor),InpFontSize);
   PutLabel("sl",RowText("SL合計",total_sl,missing_sl,error_sl),offset+1,
            !valid_sl ? InpWarningColor : (total_sl<0 ? InpLossColor : InpProfitColor),InpFontSize);
   RefreshRates(offset+2);
   PublishBuffers();
   ChartRedraw(0);
}
bool SelfTest()
{
   double rate;
   if(!SolveRate(80000,-10,4813,0,rate) || MathAbs(rate-80481.3)>1e-7) return false;
   if(!SolveRate(80000,-10,9797.95,804.814,rate) || MathAbs(rate-80899.3136)>1e-7) return false;
   if(!SolveRate(100,2,20,0,rate) || MathAbs(rate-90)>1e-7) return false;
   if(SolveRate(100,0,20,0,rate)) return false;
   if(SolveRate(100,1,200,0,rate)) return false;
   return Grouped(18813,2)=="18,813.00" &&
          Money(-2187,"USD",2)=="-2,187.00 USD" &&
          Grouped(999.999,2)=="1,000.00" &&
          Grouped(1234567.89,2)=="1,234,567.89" &&
          Money(-0.001,"USD",2)=="0.00 USD";
}
int OnInit()
{
   if(InpFontSize<8 || InpFontSize>72 || InpDecimals<0 || InpDecimals>8 ||
      InpRowSpacing<1 || InpExitCommissionPerLot<0 || InpStopOutPercent<=0 || !SelfTest())
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
   IndicatorSetString(INDICATOR_SHORTNAME,"Clean TP SL Totals");
   IndicatorSetInteger(INDICATOR_DIGITS,InpDecimals);
   account_currency=AccountInfoString(ACCOUNT_CURRENCY);
   prefix="CleanTPSL_"+IntegerToString(ChartID())+"_"+IntegerToString(GetMicrosecondCount())+"_";
   if(!EventSetTimer(1)) return INIT_FAILED;
   Refresh();
   PrintFormat("Read-only initialized. Positions=%d TP=%s SL=%s SelfTest=PASS",
               total_positions,valid_tp ? Money(total_tp,account_currency,InpDecimals) : "incomplete",
               valid_sl ? Money(total_sl,account_currency,InpDecimals) : "incomplete");
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(prefix!="") ObjectsDeleteAll(0,prefix);
   ChartRedraw(0);
}
void OnTimer() { Refresh(); }
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id==CHARTEVENT_CHART_CHANGE) Refresh();
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
   Refresh();
   return rates_total;
}
