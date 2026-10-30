// PositionScenario calculations and panel owned by PositionMonitor. No trade operations.
#define SCENARIO_PANEL_WIDTH 665
bool scenario_panel_hidden=false;

struct ScenarioPositionSnapshot
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

string ScenarioPanelPrefix()
{
   return "PositionScenario_"+IntegerToString(ChartID())+"_";
}

int ScenarioPanelX(const int offset)
{
   return InpScenarioAlignRight ? InpScenarioX+SCENARIO_PANEL_WIDTH-offset : InpScenarioX+offset;
}

string ScenarioGrouped(const double value,const int digits)
{
   string result=DoubleToString(MathAbs(value),digits);
   int dot=StringFind(result,".");
   int end=(dot<0 ? StringLen(result) : dot);
   for(int i=end-3;i>0;i-=3)
      result=StringSubstr(result,0,i)+","+StringSubstr(result,i);
   return result;
}

string ScenarioSignedMoney(const double value,const string currency)
{
   double rounded=NormalizeDouble(value,2);
   return (rounded>0 ? "+" : (rounded<0 ? "-" : ""))+ScenarioGrouped(rounded,2)+" "+currency;
}

color ScenarioAmountColor(const double amount)
{
   return amount>0 ? clrLimeGreen : (amount<0 ? clrTomato : clrWhite);
}

bool ScenarioProfitAt(const ScenarioPositionSnapshot &position,const double exit_price,double &result)
{
   result=0;
   if(exit_price<=0 || !MathIsValidNumber(exit_price)) return false;
   double gross=0;
   if(!Estimate(position.symbol,position.buy,position.lots,position.entry,exit_price,gross))
      return false;
   result=gross+(InpIncludeSwap ? position.swap : 0.0)-InpExitCommissionPerLot*position.lots;
   return MathIsValidNumber(result);
}

bool ScenarioSnapshot(ScenarioPositionSnapshot &positions[],int &count,double &account_current,
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
         ScenarioPositionSnapshot other;
         other.symbol=symbol;
         other.buy=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
         other.lots=PositionGetDouble(POSITION_VOLUME);
         other.entry=PositionGetDouble(POSITION_PRICE_OPEN);
         other.swap=PositionGetDouble(POSITION_SWAP);
         other.tp=PositionGetDouble(POSITION_TP);
         other.sl=PositionGetDouble(POSITION_SL);
         double outcome;
         if(other.tp>0 && ScenarioProfitAt(other,other.tp,outcome)) other_tp+=outcome;
         else other_tp_ok=false;
         if(other.sl>0 && ScenarioProfitAt(other,other.sl,outcome)) other_sl+=outcome;
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
      positions[count].current_tp_ok=ScenarioProfitAt(positions[count],positions[count].tp,positions[count].current_tp);
      positions[count].current_sl_ok=ScenarioProfitAt(positions[count],positions[count].sl,positions[count].current_sl);
      positions[count].trial_tp_ok=(InpTrialTP>0 && ScenarioProfitAt(positions[count],InpTrialTP,positions[count].trial_tp));
      positions[count].trial_sl_ok=(InpTrialSL>0 && ScenarioProfitAt(positions[count],InpTrialSL,positions[count].trial_sl));
      count++;
   }
   ArrayResize(positions,count);
   account_current=AccountInfoDouble(ACCOUNT_PROFIT);
   return PositionsTotal()==before && MathIsValidNumber(account_current);
}

// Rank by profit at each position's current TP; tie-break by ticket.
bool ScenarioSelectHalf(ScenarioPositionSnapshot &positions[],const int count,bool &selected[])
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
bool ScenarioSumCase(ScenarioPositionSnapshot &positions[],const int count,bool &selected[],
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

bool ScenarioSelfTest()
{
   ScenarioPositionSnapshot sample[];
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
   if(!ScenarioSelectHalf(sample,5,selected)) return false;
   if(!selected[1] || !selected[3] || selected[0] || selected[2] || selected[4]) return false;
   double result=0;
   if(!ScenarioSumCase(sample,5,selected,true,0,result) || result!=73) return false;
   if(!ScenarioSumCase(sample,5,selected,true,1,result) || result!=500) return false;
   if(!ScenarioSumCase(sample,5,selected,true,2,result) || result!=283) return false;
   if(!ScenarioSumCase(sample,5,selected,false,2,result) || result!=-206) return false;
   return true;
}

void ScenarioLabel(const string key,const string message,const int x,const int y,
           const color colour,const int size,const bool right=false)
{
   string name=ScenarioPanelPrefix()+key;
   if(!ObjectCreate(0,name,OBJ_LABEL,0,0,0)) return;
   ObjectSetString(0,name,OBJPROP_TEXT,message);
   ObjectSetString(0,name,OBJPROP_FONT,"Meiryo");
   ObjectSetInteger(0,name,OBJPROP_CORNER,InpScenarioAlignRight ? CORNER_RIGHT_UPPER : CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,right ? ANCHOR_RIGHT_UPPER : ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,size);
   ObjectSetInteger(0,name,OBJPROP_COLOR,colour);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES,scenario_panel_hidden ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);
}

void ScenarioCell(const string key,const double value,const bool valid,const string currency,
          const int right_distance,const int y,const color fixed_color=clrNONE)
{
   ScenarioLabel(key,valid ? ScenarioSignedMoney(value,currency) : "算出不可",right_distance,y,
         valid ? (fixed_color==clrNONE ? ScenarioAmountColor(value) : fixed_color) : clrOrange,
         InpFontSize,true);
}

void ScenarioDeltaCell(const string key,const double scenario,const bool scenario_ok,
               const double current,const bool current_ok,const string currency,
               const int right_distance,const int y,const color fixed_color=clrNONE)
{
   if(!scenario_ok || !current_ok)
   {
      ScenarioLabel(key,"差額 ―",right_distance,y,clrSilver,InpFontSize-1,true);
      return;
   }
   double difference=scenario-current;
   ScenarioLabel(key,"差額 "+ScenarioSignedMoney(difference,currency),right_distance,y,
         fixed_color==clrNONE ? ScenarioAmountColor(difference) : fixed_color,InpFontSize-1,true);
}

void ScenarioRender(const int count,const bool ranking_ok,
            const double &values[][3],const bool &valid[][3],
            const double account_current,const double symbol_current,
            const double other_tp,const double other_sl,
            const bool other_tp_ok,const bool other_sl_ok,const string currency)
{
   const int width=SCENARIO_PANEL_WIDTH;
   const int height=362;
   string panel=ScenarioPanelPrefix()+"background";
   if(ObjectCreate(0,panel,OBJ_RECTANGLE_LABEL,0,0,0))
   {
      ObjectSetInteger(0,panel,OBJPROP_CORNER,InpScenarioAlignRight ? CORNER_RIGHT_UPPER : CORNER_LEFT_UPPER);
      // Rectangle labels have a fixed upper-left anchor even at the right corner.
      // Offset by their width so the whole background stays inside the chart.
      ObjectSetInteger(0,panel,OBJPROP_XDISTANCE,InpScenarioAlignRight ? InpScenarioX+width : InpScenarioX);
      ObjectSetInteger(0,panel,OBJPROP_YDISTANCE,InpScenarioY);
      ObjectSetInteger(0,panel,OBJPROP_XSIZE,width);
      ObjectSetInteger(0,panel,OBJPROP_YSIZE,height);
      ObjectSetInteger(0,panel,OBJPROP_BGCOLOR,C'22,24,29');
      ObjectSetInteger(0,panel,OBJPROP_COLOR,C'90,95,103');
      ObjectSetInteger(0,panel,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(0,panel,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,panel,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,panel,OBJPROP_BACK,false);
      ObjectSetInteger(0,panel,OBJPROP_TIMEFRAMES,scenario_panel_hidden ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);
   }
   int left=ScenarioPanelX(16);
   int condition=ScenarioPanelX(123);
   int current=ScenarioPanelX(278);
   int all=ScenarioPanelX(462);
   int half=ScenarioPanelX(648);
   ScenarioLabel("title","Position Scenario  |  "+_Symbol+"  |  "+IntegerToString(count)+"件 / 半数"+
         IntegerToString(count/2)+"件",left,InpScenarioY+11,clrWhite,InpFontSize+1);
   ScenarioLabel("timestamp","試算時刻 "+TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS)+
         "  /  口座通貨 "+currency,left,InpScenarioY+36,clrSilver,InpFontSize-1);
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   ScenarioLabel("planned_label","仮設定",left,InpScenarioY+60,clrWhite,InpFontSize);
   ScenarioLabel("planned_tp",InpTrialTP>0 ? "TP → "+ScenarioGrouped(InpTrialTP,digits) : "TP → 未入力",
         ScenarioPanelX(111),InpScenarioY+60,InpTrialTP>0 ? clrLimeGreen : clrOrange,InpFontSize+1);
   ScenarioLabel("planned_sl",InpTrialSL>0 ? "SL → "+ScenarioGrouped(InpTrialSL,digits) : "SL → 未入力",
         ScenarioPanelX(336),InpScenarioY+60,InpTrialSL>0 ? clrRed : clrOrange,InpFontSize+1);
   ScenarioLabel("symbol_current",_Symbol+" 現在損益  "+ScenarioSignedMoney(symbol_current,currency),
         left,InpScenarioY+84,ScenarioAmountColor(symbol_current),InpFontSize);
   ScenarioLabel("account_current","口座現在損益  "+ScenarioSignedMoney(account_current,currency),
         ScenarioPanelX(335),InpScenarioY+84,ScenarioAmountColor(account_current),InpFontSize);
   ObjectSetString(0,ScenarioPanelPrefix()+"symbol_current",OBJPROP_TOOLTIP,
                   "チャート銘柄のPOSITION_PROFIT合計。スワップは含みません。");
   ObjectSetString(0,ScenarioPanelPrefix()+"account_current",OBJPROP_TOOLTIP,
                   "口座全体のACCOUNT_PROFIT。スワップは含みません。");
   ScenarioLabel("h_current","現状",current,InpScenarioY+112,clrWhite,InpFontSize,true);
   ScenarioLabel("h_all","全件変更",all,InpScenarioY+112,clrWhite,InpFontSize,true);
   ScenarioLabel("h_half","半数変更",half,InpScenarioY+112,clrWhite,InpFontSize,true);
   ScenarioLabel("tp_title","TP",condition,InpScenarioY+139,clrLimeGreen,InpFontSize,true);
   ScenarioLabel("tp_account_title","TP合計(口座)",condition,InpScenarioY+162,clrWhite,InpFontSize-1,true);
   ScenarioLabel("sl_title","SL",condition,InpScenarioY+215,clrRed,InpFontSize,true);
   ScenarioLabel("sl_account_title","SL合計(口座)",condition,InpScenarioY+238,clrRed,InpFontSize-1,true);
   ScenarioCell("tp_now",values[0][0],valid[0][0],currency,current,InpScenarioY+139);
   ScenarioCell("tp_all",values[0][1],valid[0][1],currency,all,InpScenarioY+139);
   ScenarioCell("tp_half",values[0][2],valid[0][2],currency,half,InpScenarioY+139);
   ScenarioCell("tp_account_now",other_tp+values[0][0],other_tp_ok && valid[0][0],currency,current,InpScenarioY+162);
   ScenarioCell("tp_account_all",other_tp+values[0][1],other_tp_ok && valid[0][1],currency,all,InpScenarioY+162);
   ScenarioCell("tp_account_half",other_tp+values[0][2],other_tp_ok && valid[0][2],currency,half,InpScenarioY+162);
   ScenarioDeltaCell("tp_all_delta",values[0][1],valid[0][1],values[0][0],valid[0][0],currency,all,InpScenarioY+185);
   ScenarioDeltaCell("tp_half_delta",values[0][2],valid[0][2],values[0][0],valid[0][0],currency,half,InpScenarioY+185);
   ScenarioCell("sl_now",values[1][0],valid[1][0],currency,current,InpScenarioY+215,clrRed);
   ScenarioCell("sl_all",values[1][1],valid[1][1],currency,all,InpScenarioY+215,clrRed);
   ScenarioCell("sl_half",values[1][2],valid[1][2],currency,half,InpScenarioY+215,clrRed);
   ScenarioCell("sl_account_now",other_sl+values[1][0],other_sl_ok && valid[1][0],currency,current,InpScenarioY+238,clrRed);
   ScenarioCell("sl_account_all",other_sl+values[1][1],other_sl_ok && valid[1][1],currency,all,InpScenarioY+238,clrRed);
   ScenarioCell("sl_account_half",other_sl+values[1][2],other_sl_ok && valid[1][2],currency,half,InpScenarioY+238,clrRed);
   ScenarioDeltaCell("sl_all_delta",values[1][1],valid[1][1],values[1][0],valid[1][0],currency,all,InpScenarioY+261,clrRed);
   ScenarioDeltaCell("sl_half_delta",values[1][2],valid[1][2],values[1][0],valid[1][0],currency,half,InpScenarioY+261,clrRed);
   string rule=ranking_ok ? "半数は現在TPの見込利益が低い順（奇数件は切り捨て）" :
                           "半数の選択不可：現在TPが未設定、または損益を計算できません";
   ScenarioLabel("rule",rule,left,InpScenarioY+289,ranking_ok ? clrSilver : clrOrange,InpFontSize-1);
   string account_note=(other_tp_ok && other_sl_ok) ?
      "口座全体: 他銘柄は現在設定のTP/SLで試算" :
      "他銘柄にTP/SL未設定または計算不可あり: 対象の口座合計は算出不可";
   ScenarioLabel("account_note",account_note,left,InpScenarioY+311,
         (other_tp_ok && other_sl_ok) ? clrSilver : clrOrange,InpFontSize-1);
   string basis=SymbolInfoString(_Symbol,SYMBOL_CURRENCY_PROFIT)==currency ?
                "仮価格での見積り" : "為替換算は試算時点";
   ScenarioLabel("note",(InpIncludeSwap ? "TP/SL試算: Swap込" : "TP/SL試算: Swap除外")+
                "  |  現在損益: Swap除外  |  "+basis+"  |  実際のTP/SLは変更しません",
         left,InpScenarioY+333,clrSilver,InpFontSize-1);
   ChartRedraw(0);
}

void ScenarioShowMessage(const string message)
{
   ScenarioLabel("message",message,ScenarioPanelX(25),InpScenarioY+20,clrOrange,InpFontSize);
   ChartRedraw(0);
   Print("PositionScenario: "+message);
}

void ScenarioRun()
{
   scenario_panel_hidden=false;
   ObjectsDeleteAll(0,ScenarioPanelPrefix());
   if(InpTrialTP<0 || InpTrialSL<0 || InpExitCommissionPerLot<0 ||
      InpFontSize<8 || InpFontSize>72 || InpScenarioX<0 || InpScenarioY<0 || !ScenarioSelfTest())
   {
      ScenarioShowMessage("入力値または自己検証が不正です。");
      return;
   }
   ScenarioPositionSnapshot positions[];
   int count=0;
   double account_current=0,symbol_current=0,other_tp=0,other_sl=0;
   bool other_tp_ok=false,other_sl_ok=false;
   if(!ScenarioSnapshot(positions,count,account_current,symbol_current,
                other_tp,other_sl,other_tp_ok,other_sl_ok))
   {
      ScenarioShowMessage("ポジション取得中に状態が変化しました。再実行してください。");
      return;
   }
   if(count==0)
   {
      ScenarioShowMessage(_Symbol+" の保有ポジションはありません。");
      return;
   }
   bool selected[];
   bool ranking_ok=ScenarioSelectHalf(positions,count,selected);
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
                           ScenarioSumCase(positions,count,selected,tp,mode,values[kind][mode]);
      }
   }
   string currency=AccountInfoString(ACCOUNT_CURRENCY);
   ScenarioRender(count,ranking_ok,values,valid,account_current,symbol_current,other_tp,other_sl,
          other_tp_ok,other_sl_ok,currency);
   PrintFormat("PositionScenario totals: TP current=%s all=%s half=%s; SL current=%s all=%s half=%s",
               valid[0][0] ? ScenarioSignedMoney(values[0][0],currency) : "unavailable",
               valid[0][1] ? ScenarioSignedMoney(values[0][1],currency) : "unavailable",
               valid[0][2] ? ScenarioSignedMoney(values[0][2],currency) : "unavailable",
               valid[1][0] ? ScenarioSignedMoney(values[1][0],currency) : "unavailable",
               valid[1][1] ? ScenarioSignedMoney(values[1][1],currency) : "unavailable",
               valid[1][2] ? ScenarioSignedMoney(values[1][2],currency) : "unavailable");
   PrintFormat("PositionScenario: %s %d positions, half %d, symbol current %.2f, account current %.2f, other TP %s, other SL %s. No orders or positions modified.",
               _Symbol,count,count/2,symbol_current,account_current,
               other_tp_ok ? ScenarioSignedMoney(other_tp,currency) : "unavailable",
               other_sl_ok ? ScenarioSignedMoney(other_sl,currency) : "unavailable");
}

// Trial outcomes change only when a position or its exit settings change.
string ScenarioPositionKey()
{
   string key=IntegerToString(PositionsTotal());
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) return "unavailable";
      key+="|"+IntegerToString((long)ticket)+":"+PositionGetString(POSITION_SYMBOL)+":"+
           IntegerToString(PositionGetInteger(POSITION_TYPE))+":"+
           DoubleToString(PositionGetDouble(POSITION_VOLUME),8)+":"+
           DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN),8)+":"+
           DoubleToString(PositionGetDouble(POSITION_TP),8)+":"+
           DoubleToString(PositionGetDouble(POSITION_SL),8)+":"+
           DoubleToString(PositionGetDouble(POSITION_SWAP),8);
   }
   return key;
}

void ScenarioRefreshCurrent()
{
   string symbol_name=ScenarioPanelPrefix()+"symbol_current";
   string account_name=ScenarioPanelPrefix()+"account_current";
   if(ObjectFind(0,symbol_name)<0 || ObjectFind(0,account_name)<0) return;
   double symbol_profit=0;
   for(int i=0;i<PositionsTotal();i++)
   {
      if(PositionGetTicket(i)==0) return;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol)
         symbol_profit+=PositionGetDouble(POSITION_PROFIT);
   }
   double account_profit=AccountInfoDouble(ACCOUNT_PROFIT);
   string currency=AccountInfoString(ACCOUNT_CURRENCY);
   ObjectSetString(0,symbol_name,OBJPROP_TEXT,
                   _Symbol+" 現在損益  "+ScenarioSignedMoney(symbol_profit,currency));
   ObjectSetInteger(0,symbol_name,OBJPROP_COLOR,ScenarioAmountColor(symbol_profit));
   ObjectSetString(0,account_name,OBJPROP_TEXT,
                   "口座現在損益  "+ScenarioSignedMoney(account_profit,currency));
   ObjectSetInteger(0,account_name,OBJPROP_COLOR,ScenarioAmountColor(account_profit));
   ChartRedraw(0);
}
