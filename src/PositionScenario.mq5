// Read-only, one-shot TP/SL comparison. No order or position modification.
#property script_show_inputs
#property description "Preview TP/SL outcomes for all or half of the current symbol positions."

input double InpTrialTP=0.0;                 // 仮TP価格（0=試算しない）
input double InpTrialSL=0.0;                 // 仮SL価格（0=試算しない）
input bool InpIncludeSwap=true;             // 発生済みスワップを含める
input double InpExitCommissionPerLot=0.0;   // 決済手数料/lot（片道・口座通貨）
input bool InpClearResult=false;            // 前回の表示を消すだけ
input bool InpAlignRight=false;             // false=左上、true=右上
input int InpX=15;                          // 選択した側の端からの距離 px
input int InpY=25;                          // 上端からの距離 px
input int InpFontSize=11;                   // フォントサイズ

#define SCENARIO_PANEL_WIDTH 665
bool hidden_by_monitor=false;

struct PositionSnapshot
{
   ulong ticket;
   string symbol;
   bool buy;
   double lots;
   double entry;
   double swap;
   double tp;
   double sl;
   double current_tp;
   double current_sl;
   double trial_tp;
   double trial_sl;
   bool current_tp_ok;
   bool current_sl_ok;
   bool trial_tp_ok;
   bool trial_sl_ok;
};

string Prefix()
{
   return "PositionScenario_"+IntegerToString(ChartID())+"_";
}

int PanelX(const int offset)
{
   return InpAlignRight ? InpX+SCENARIO_PANEL_WIDTH-offset : InpX+offset;
}

string Grouped(const double value,const int digits)
{
   string result=DoubleToString(MathAbs(value),digits);
   int dot=StringFind(result,".");
   int end=(dot<0 ? StringLen(result) : dot);
   for(int i=end-3;i>0;i-=3)
      result=StringSubstr(result,0,i)+","+StringSubstr(result,i);
   return result;
}

string SignedMoney(const double value,const string currency)
{
   double rounded=NormalizeDouble(value,2);
   return (rounded>0 ? "+" : (rounded<0 ? "-" : ""))+Grouped(rounded,2)+" "+currency;
}

color AmountColor(const double amount)
{
   return amount>0 ? clrLimeGreen : (amount<0 ? clrTomato : clrWhite);
}

bool ProfitAt(const PositionSnapshot &position,const double exit_price,double &result)
{
   result=0;
   if(exit_price<=0 || !MathIsValidNumber(exit_price)) return false;
   double gross=0;
   ENUM_ORDER_TYPE side=position.buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcProfit(side,position.symbol,position.lots,position.entry,exit_price,gross))
      return false;
   result=gross+(InpIncludeSwap ? position.swap : 0.0)-InpExitCommissionPerLot*position.lots;
   return MathIsValidNumber(result);
}

bool Snapshot(PositionSnapshot &positions[],int &count,double &account_current,
              double &symbol_current,
              double &other_tp,double &other_sl,bool &other_tp_ok,bool &other_sl_ok)
{
   count=0;
   account_current=0;
   symbol_current=0;
   other_tp=0;
   other_sl=0;
   other_tp_ok=true;
   other_sl_ok=true;
   int before=PositionsTotal();
   ArrayResize(positions,before);
   for(int i=0;i<before;i++)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) return false;
      double live=PositionGetDouble(POSITION_PROFIT);
      if(!MathIsValidNumber(live)) return false;
      string symbol=PositionGetString(POSITION_SYMBOL);
      if(symbol==_Symbol) symbol_current+=live;
      if(symbol!=_Symbol)
      {
         PositionSnapshot other;
         other.symbol=symbol;
         other.buy=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
         other.lots=PositionGetDouble(POSITION_VOLUME);
         other.entry=PositionGetDouble(POSITION_PRICE_OPEN);
         other.swap=PositionGetDouble(POSITION_SWAP);
         other.tp=PositionGetDouble(POSITION_TP);
         other.sl=PositionGetDouble(POSITION_SL);
         double outcome;
         if(other.tp>0 && ProfitAt(other,other.tp,outcome)) other_tp+=outcome;
         else other_tp_ok=false;
         if(other.sl>0 && ProfitAt(other,other.sl,outcome)) other_sl+=outcome;
         else other_sl_ok=false;
         continue;
      }
      positions[count].ticket=ticket;
      positions[count].symbol=symbol;
      positions[count].buy=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
      positions[count].lots=PositionGetDouble(POSITION_VOLUME);
      positions[count].entry=PositionGetDouble(POSITION_PRICE_OPEN);
      positions[count].swap=PositionGetDouble(POSITION_SWAP);
      positions[count].tp=PositionGetDouble(POSITION_TP);
      positions[count].sl=PositionGetDouble(POSITION_SL);
      positions[count].current_tp_ok=ProfitAt(positions[count],positions[count].tp,positions[count].current_tp);
      positions[count].current_sl_ok=ProfitAt(positions[count],positions[count].sl,positions[count].current_sl);
      positions[count].trial_tp_ok=(InpTrialTP>0 && ProfitAt(positions[count],InpTrialTP,positions[count].trial_tp));
      positions[count].trial_sl_ok=(InpTrialSL>0 && ProfitAt(positions[count],InpTrialSL,positions[count].trial_sl));
      count++;
   }
   ArrayResize(positions,count);
   account_current=AccountInfoDouble(ACCOUNT_PROFIT);
   return PositionsTotal()==before && MathIsValidNumber(account_current);
}

// Rank by profit at each position's current TP; tie-break by ticket.
bool SelectHalf(PositionSnapshot &positions[],const int count,bool &selected[])
{
   ArrayResize(selected,count);
   for(int i=0;i<count;i++)
   {
      selected[i]=false;
      if(!positions[i].current_tp_ok) return false;
   }
   int order[];
   ArrayResize(order,count);
   for(int i=0;i<count;i++) order[i]=i;
   for(int i=1;i<count;i++)
   {
      int chosen=order[i];
      int j=i-1;
      while(j>=0 && (positions[order[j]].current_tp>positions[chosen].current_tp ||
                     (positions[order[j]].current_tp==positions[chosen].current_tp &&
                      positions[order[j]].ticket>positions[chosen].ticket)))
      {
         order[j+1]=order[j];
         j--;
      }
      order[j+1]=chosen;
   }
   for(int i=0;i<count/2;i++) selected[order[i]]=true;
   return true;
}

// mode: 0=current, 1=change all, 2=change selected half.
bool SumCase(PositionSnapshot &positions[],const int count,bool &selected[],
             const bool tp,const int mode,double &sum)
{
   sum=0;
   for(int i=0;i<count;i++)
   {
      bool use_trial=(mode==1 || (mode==2 && selected[i]));
      bool valid=tp ? (use_trial ? positions[i].trial_tp_ok : positions[i].current_tp_ok)
                    : (use_trial ? positions[i].trial_sl_ok : positions[i].current_sl_ok);
      if(!valid) return false;
      sum+=tp ? (use_trial ? positions[i].trial_tp : positions[i].current_tp)
              : (use_trial ? positions[i].trial_sl : positions[i].current_sl);
   }
   return true;
}

bool SelfTest()
{
   PositionSnapshot sample[];
   ArrayResize(sample,5);
   double profits[5]={40,-10,40,0,3};
   for(int i=0;i<5;i++)
   {
      sample[i].ticket=(ulong)(100+i);
      sample[i].current_tp=profits[i];
      sample[i].current_tp_ok=true;
      sample[i].current_sl=(double)(-i);
      sample[i].current_sl_ok=true;
      sample[i].trial_tp=100;
      sample[i].trial_tp_ok=true;
      sample[i].trial_sl=-100;
      sample[i].trial_sl_ok=true;
   }
   bool selected[];
   if(!SelectHalf(sample,5,selected)) return false;
   if(!selected[1] || !selected[3] || selected[0] || selected[2] || selected[4]) return false;
   double result=0;
   if(!SumCase(sample,5,selected,true,0,result) || result!=73) return false;
   if(!SumCase(sample,5,selected,true,1,result) || result!=500) return false;
   if(!SumCase(sample,5,selected,true,2,result) || result!=283) return false;
   if(!SumCase(sample,5,selected,false,2,result) || result!=-206) return false;
   return true;
}

void Label(const string key,const string message,const int x,const int y,
           const color colour,const int size,const bool right=false)
{
   string name=Prefix()+key;
   if(!ObjectCreate(0,name,OBJ_LABEL,0,0,0)) return;
   ObjectSetString(0,name,OBJPROP_TEXT,message);
   ObjectSetString(0,name,OBJPROP_FONT,"Meiryo");
   ObjectSetInteger(0,name,OBJPROP_CORNER,InpAlignRight ? CORNER_RIGHT_UPPER : CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,right ? ANCHOR_RIGHT_UPPER : ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,size);
   ObjectSetInteger(0,name,OBJPROP_COLOR,colour);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES,hidden_by_monitor ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);
}

void Cell(const string key,const double value,const bool valid,const string currency,
          const int right_distance,const int y,const color fixed_color=clrNONE)
{
   Label(key,valid ? SignedMoney(value,currency) : "算出不可",right_distance,y,
         valid ? (fixed_color==clrNONE ? AmountColor(value) : fixed_color) : clrOrange,
         InpFontSize,true);
}

void DeltaCell(const string key,const double scenario,const bool scenario_ok,
               const double current,const bool current_ok,const string currency,
               const int right_distance,const int y,const color fixed_color=clrNONE)
{
   if(!scenario_ok || !current_ok)
   {
      Label(key,"差額 ―",right_distance,y,clrSilver,InpFontSize-1,true);
      return;
   }
   double difference=scenario-current;
   Label(key,"差額 "+SignedMoney(difference,currency),right_distance,y,
         fixed_color==clrNONE ? AmountColor(difference) : fixed_color,InpFontSize-1,true);
}

void Render(const int count,const bool ranking_ok,
            const double &values[][3],const bool &valid[][3],
            const double account_current,const double symbol_current,
            const double other_tp,const double other_sl,
            const bool other_tp_ok,const bool other_sl_ok,const string currency)
{
   const int width=SCENARIO_PANEL_WIDTH;
   const int height=362;
   string panel=Prefix()+"background";
   if(ObjectCreate(0,panel,OBJ_RECTANGLE_LABEL,0,0,0))
   {
      ObjectSetInteger(0,panel,OBJPROP_CORNER,InpAlignRight ? CORNER_RIGHT_UPPER : CORNER_LEFT_UPPER);
      // Rectangle labels have a fixed upper-left anchor even at the right corner.
      // Offset by their width so the whole background stays inside the chart.
      ObjectSetInteger(0,panel,OBJPROP_XDISTANCE,InpAlignRight ? InpX+width : InpX);
      ObjectSetInteger(0,panel,OBJPROP_YDISTANCE,InpY);
      ObjectSetInteger(0,panel,OBJPROP_XSIZE,width);
      ObjectSetInteger(0,panel,OBJPROP_YSIZE,height);
      ObjectSetInteger(0,panel,OBJPROP_BGCOLOR,C'22,24,29');
      ObjectSetInteger(0,panel,OBJPROP_COLOR,C'90,95,103');
      ObjectSetInteger(0,panel,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(0,panel,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,panel,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,panel,OBJPROP_BACK,false);
      ObjectSetInteger(0,panel,OBJPROP_TIMEFRAMES,hidden_by_monitor ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);
   }
   int left=PanelX(16);
   int condition=PanelX(123);
   int current=PanelX(278);
   int all=PanelX(462);
   int half=PanelX(648);
   Label("title","Position Scenario  |  "+_Symbol+"  |  "+IntegerToString(count)+"件 / 半数"+
         IntegerToString(count/2)+"件",left,InpY+11,clrWhite,InpFontSize+1);
   Label("timestamp","試算時刻 "+TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS)+
         "  /  口座通貨 "+currency,left,InpY+36,clrSilver,InpFontSize-1);
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   Label("planned_label","仮設定",left,InpY+60,clrWhite,InpFontSize);
   Label("planned_tp",InpTrialTP>0 ? "TP → "+Grouped(InpTrialTP,digits) : "TP → 未入力",
         PanelX(111),InpY+60,InpTrialTP>0 ? clrLimeGreen : clrOrange,InpFontSize+1);
   Label("planned_sl",InpTrialSL>0 ? "SL → "+Grouped(InpTrialSL,digits) : "SL → 未入力",
         PanelX(336),InpY+60,InpTrialSL>0 ? clrRed : clrOrange,InpFontSize+1);
   Label("symbol_current",_Symbol+" 現在損益  "+SignedMoney(symbol_current,currency),
         left,InpY+84,AmountColor(symbol_current),InpFontSize);
   Label("account_current","口座現在損益  "+SignedMoney(account_current,currency),
         PanelX(335),InpY+84,AmountColor(account_current),InpFontSize);
   ObjectSetString(0,Prefix()+"symbol_current",OBJPROP_TOOLTIP,
                   "チャート銘柄のPOSITION_PROFIT合計。スワップは含みません。");
   ObjectSetString(0,Prefix()+"account_current",OBJPROP_TOOLTIP,
                   "口座全体のACCOUNT_PROFIT。スワップは含みません。");
   Label("h_current","現状",current,InpY+112,clrWhite,InpFontSize,true);
   Label("h_all","全件変更",all,InpY+112,clrWhite,InpFontSize,true);
   Label("h_half","半数変更",half,InpY+112,clrWhite,InpFontSize,true);
   Label("tp_title","TP",condition,InpY+139,clrLimeGreen,InpFontSize,true);
   Label("tp_account_title","TP合計(口座)",condition,InpY+162,clrWhite,InpFontSize-1,true);
   Label("sl_title","SL",condition,InpY+215,clrRed,InpFontSize,true);
   Label("sl_account_title","SL合計(口座)",condition,InpY+238,clrRed,InpFontSize-1,true);
   Cell("tp_now",values[0][0],valid[0][0],currency,current,InpY+139);
   Cell("tp_all",values[0][1],valid[0][1],currency,all,InpY+139);
   Cell("tp_half",values[0][2],valid[0][2],currency,half,InpY+139);
   Cell("tp_account_now",other_tp+values[0][0],other_tp_ok && valid[0][0],currency,current,InpY+162);
   Cell("tp_account_all",other_tp+values[0][1],other_tp_ok && valid[0][1],currency,all,InpY+162);
   Cell("tp_account_half",other_tp+values[0][2],other_tp_ok && valid[0][2],currency,half,InpY+162);
   DeltaCell("tp_all_delta",values[0][1],valid[0][1],values[0][0],valid[0][0],currency,all,InpY+185);
   DeltaCell("tp_half_delta",values[0][2],valid[0][2],values[0][0],valid[0][0],currency,half,InpY+185);
   Cell("sl_now",values[1][0],valid[1][0],currency,current,InpY+215,clrRed);
   Cell("sl_all",values[1][1],valid[1][1],currency,all,InpY+215,clrRed);
   Cell("sl_half",values[1][2],valid[1][2],currency,half,InpY+215,clrRed);
   Cell("sl_account_now",other_sl+values[1][0],other_sl_ok && valid[1][0],currency,current,InpY+238,clrRed);
   Cell("sl_account_all",other_sl+values[1][1],other_sl_ok && valid[1][1],currency,all,InpY+238,clrRed);
   Cell("sl_account_half",other_sl+values[1][2],other_sl_ok && valid[1][2],currency,half,InpY+238,clrRed);
   DeltaCell("sl_all_delta",values[1][1],valid[1][1],values[1][0],valid[1][0],currency,all,InpY+261,clrRed);
   DeltaCell("sl_half_delta",values[1][2],valid[1][2],values[1][0],valid[1][0],currency,half,InpY+261,clrRed);
   string rule=ranking_ok ? "半数は現在TPの見込利益が低い順（奇数件は切り捨て）" :
                           "半数の選択不可：現在TPが未設定、または損益を計算できません";
   Label("rule",rule,left,InpY+289,ranking_ok ? clrSilver : clrOrange,InpFontSize-1);
   string account_note=(other_tp_ok && other_sl_ok) ?
      "口座全体: 他銘柄は現在設定のTP/SLで試算" :
      "他銘柄にTP/SL未設定または計算不可あり: 対象の口座合計は算出不可";
   Label("account_note",account_note,left,InpY+311,
         (other_tp_ok && other_sl_ok) ? clrSilver : clrOrange,InpFontSize-1);
   string basis=SymbolInfoString(_Symbol,SYMBOL_CURRENCY_PROFIT)==currency ?
                "仮価格での見積り" : "為替換算は試算時点";
   Label("note",(InpIncludeSwap ? "TP/SL試算: Swap込" : "TP/SL試算: Swap除外")+
                "  |  現在損益: Swap除外  |  "+basis+"  |  実際のTP/SLは変更しません",
         left,InpY+333,clrSilver,InpFontSize-1);
   ChartRedraw(0);
}

void ShowMessage(const string message)
{
   Label("message",message,PanelX(25),InpY+20,clrOrange,InpFontSize);
   ChartRedraw(0);
   Print("PositionScenario: "+message);
}

void OnStart()
{
   string toggle="PositionMonitor_"+IntegerToString(ChartID())+"_toggle_scenario";
   hidden_by_monitor=ObjectFind(0,toggle)>=0 &&
                     StringFind(ObjectGetString(0,toggle,OBJPROP_TEXT),"を表示")>=0;
   ObjectsDeleteAll(0,Prefix());
   if(InpClearResult) { ChartRedraw(0); return; }
   if(InpTrialTP<0 || InpTrialSL<0 || InpExitCommissionPerLot<0 ||
      InpFontSize<8 || InpFontSize>32 || InpX<0 || InpY<0 || !SelfTest())
   {
      ShowMessage("入力値または自己検証が不正です。");
      return;
   }
   PositionSnapshot positions[];
   int count=0;
   double account_current=0,symbol_current=0,other_tp=0,other_sl=0;
   bool other_tp_ok=false,other_sl_ok=false;
   if(!Snapshot(positions,count,account_current,symbol_current,
                other_tp,other_sl,other_tp_ok,other_sl_ok))
   {
      ShowMessage("ポジション取得中に状態が変化しました。再実行してください。");
      return;
   }
   if(count==0)
   {
      ShowMessage(_Symbol+" の保有ポジションはありません。");
      return;
   }
   bool selected[];
   bool ranking_ok=SelectHalf(positions,count,selected);
   double values[2][3];
   bool valid[2][3];
   for(int kind=0;kind<2;kind++)
   {
      bool tp=kind==0;
      for(int mode=0;mode<3;mode++)
      {
         values[kind][mode]=0;
         valid[kind][mode]=(mode!=2 || ranking_ok) &&
                           (mode==0 || (tp ? InpTrialTP>0 : InpTrialSL>0)) &&
                           SumCase(positions,count,selected,tp,mode,values[kind][mode]);
      }
   }
   string currency=AccountInfoString(ACCOUNT_CURRENCY);
   Render(count,ranking_ok,values,valid,account_current,symbol_current,other_tp,other_sl,
          other_tp_ok,other_sl_ok,currency);
   PrintFormat("PositionScenario: %s %d positions, half %d, symbol current %.2f, account current %.2f, other TP %s, other SL %s. No orders or positions modified.",
               _Symbol,count,count/2,symbol_current,account_current,
               other_tp_ok ? SignedMoney(other_tp,currency) : "unavailable",
               other_sl_ok ? SignedMoney(other_sl,currency) : "unavailable");
}
