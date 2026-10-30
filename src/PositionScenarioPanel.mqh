// PositionScenario calculations and panel owned by PositionMonitor. No trade operations.
#define SCENARIO_PANEL_WIDTH 585
bool scenario_panel_hidden=false;
string scenario_label_names[];

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
   return amount>0 ? clrLimeGreen : (amount<0 ? clrRed : clrWhite);
}

color ScenarioResultColor(const double amount,const bool valid,const string status)
{
   if(valid) return ScenarioAmountColor(amount);
   return status=="未設定あり" ? clrYellow : (status=="未試算" ? clrWhite : clrOrange);
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
              double &other_tp,double &other_sl,bool &other_tp_ok,bool &other_sl_ok,
              bool &other_tp_missing,bool &other_sl_missing)
{
   count=0;
   account_current=0;
   symbol_current=0;
   other_tp=0;
   other_sl=0;
   other_tp_ok=true;
   other_sl_ok=true;
   other_tp_missing=false;
   other_sl_missing=false;
   int before=PositionsTotal();
   ArrayResize(positions,before);
   for(int i=0;i<before;i++)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) return false;
      double live=PositionGetDouble(POSITION_PROFIT);
      if(!MathIsValidNumber(live)) return false;
      string symbol=PositionGetString(POSITION_SYMBOL);
      if(symbol==_Symbol) symbol_current+=live+PositionGetDouble(POSITION_SWAP);
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
         if(other.tp<=0) other_tp_missing=true;
         if(other.sl<=0) other_sl_missing=true;
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

bool ScenarioHasUnsetExit(ScenarioPositionSnapshot &positions[],const int count,
                          bool &selected[],const bool tp,const int mode)
{
   for(int i=0;i<count;i++)
   {
      bool use_trial=(mode==1 || (mode==2 && selected[i]));
      if(!use_trial && (tp ? positions[i].tp<=0 : positions[i].sl<=0)) return true;
   }
   return false;
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
   int index=ArraySize(scenario_label_names);
   ArrayResize(scenario_label_names,index+1);
   scenario_label_names[index]=name;
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
          const int right_distance,const int y,const string invalid_text)
{
   ScenarioLabel(key,valid ? ScenarioSignedMoney(value,currency) :
         (invalid_text=="未試算" ? "0 "+currency : invalid_text),right_distance,y,
         ScenarioResultColor(value,valid,invalid_text),InpFontSize,true);
}

void ScenarioDeltaCell(const string key,const double scenario,const bool scenario_ok,
               const double current,const bool current_ok,const string currency,
               const int right_distance,const int y,const bool trial_set)
{
   if(!trial_set)
   {
      ScenarioLabel(key,"0 "+currency,right_distance,y,clrWhite,InpFontSize,true);
      return;
   }
   if(!scenario_ok || !current_ok)
   {
      ScenarioLabel(key,"―",right_distance,y,clrWhite,InpFontSize,true);
      return;
   }
   double difference=scenario-current;
   ScenarioLabel(key,ScenarioSignedMoney(difference,currency),right_distance,y,
         ScenarioAmountColor(difference),InpFontSize,true);
}

void ScenarioRender(const int count,const bool ranking_ok,
            const double all_lots,const double half_lots,
            const double &values[][3],const bool &valid[][3],
            const string &status[][3],const bool other_tp_missing,const bool other_sl_missing,
            const double account_current,const double symbol_current,
            const double other_tp,const double other_sl,
            const bool other_tp_ok,const bool other_sl_ok,const string currency)
{
   const int width=SCENARIO_PANEL_WIDTH;
   const int height=342;
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
   int label_end=ScenarioPanelX(123);
   int trial_value=ScenarioPanelX(165);
   int current=ScenarioPanelX(278);
   int all=ScenarioPanelX(423);
   int half=ScenarioPanelX(568);
   ScenarioLabel("title","Position Scenario  |  "+_Symbol+"  |  "+IntegerToString(count)+"ポジション",
         left,InpScenarioY+11,clrWhite,InpFontSize+1);
   ScenarioLabel("timestamp","試算時刻 "+TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS),
         left,InpScenarioY+36,clrWhite,InpFontSize);
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   ScenarioLabel("planned_tp","TP(変更予定)",label_end,InpScenarioY+60,
         InpTrialTP>0 ? clrLimeGreen : clrOrange,InpFontSize,true);
   ScenarioLabel("planned_tp_value",InpTrialTP>0 ? ScenarioGrouped(InpTrialTP,digits) : "未入力",
         trial_value,InpScenarioY+60,InpTrialTP>0 ? clrLimeGreen : clrOrange,InpFontSize);
   ScenarioLabel("planned_sl","SL(変更予定)",label_end,InpScenarioY+84,
         InpTrialSL>0 ? clrRed : clrOrange,InpFontSize,true);
   ScenarioLabel("planned_sl_value",InpTrialSL>0 ? ScenarioGrouped(InpTrialSL,digits) : "未入力",
         trial_value,InpScenarioY+84,InpTrialSL>0 ? clrRed : clrOrange,InpFontSize);
   ScenarioLabel("symbol_current","現在損益(銘柄)",label_end,InpScenarioY+108,
         ScenarioAmountColor(symbol_current),InpFontSize,true);
   ScenarioLabel("symbol_current_value",ScenarioSignedMoney(symbol_current,currency),current,
         InpScenarioY+108,ScenarioAmountColor(symbol_current),InpFontSize,true);
   ScenarioLabel("account_current","現在損益(口座)",label_end,InpScenarioY+132,
         ScenarioAmountColor(account_current),InpFontSize,true);
   ScenarioLabel("account_current_value",ScenarioSignedMoney(account_current,currency),current,
         InpScenarioY+132,ScenarioAmountColor(account_current),InpFontSize,true);
   ObjectSetString(0,ScenarioPanelPrefix()+"symbol_current",OBJPROP_TOOLTIP,
                   "チャート銘柄のPOSITION_PROFITと発生済みPOSITION_SWAPの合計です。");
   ObjectSetString(0,ScenarioPanelPrefix()+"account_current",OBJPROP_TOOLTIP,
                   "口座全体のACCOUNT_PROFIT。この口座では発生済みスワップを反映しています。");
   ObjectSetString(0,ScenarioPanelPrefix()+"symbol_current_value",OBJPROP_TOOLTIP,
                   "チャート銘柄のPOSITION_PROFITと発生済みPOSITION_SWAPの合計です。");
   ObjectSetString(0,ScenarioPanelPrefix()+"account_current_value",OBJPROP_TOOLTIP,
                   "口座全体のACCOUNT_PROFIT。この口座では発生済みスワップを反映しています。");
   ScenarioLabel("h_current","現在の損益",current,InpScenarioY+160,clrWhite,InpFontSize,true);
   ScenarioLabel("h_all","全"+LotsText(all_lots)+" ロット変更",all,InpScenarioY+160,clrWhite,InpFontSize,true);
   ScenarioLabel("h_half",ranking_ok ? "半数"+LotsText(half_lots)+" ロット変更" : "半数変更不可",
                 half,InpScenarioY+160,clrWhite,InpFontSize,true);
   color tp_symbol_color=ScenarioResultColor(values[0][0],valid[0][0],status[0][0]);
   color sl_symbol_color=ScenarioResultColor(values[1][0],valid[1][0],status[1][0]);
   color tp_account_color=ScenarioResultColor(other_tp+values[0][0],other_tp_ok && valid[0][0],
         other_tp_missing ? "未設定あり" : status[0][0]);
   color sl_account_color=ScenarioResultColor(other_sl+values[1][0],other_sl_ok && valid[1][0],
         other_sl_missing ? "未設定あり" : status[1][0]);
   ScenarioLabel("tp_title","TP合計(銘柄)",label_end,InpScenarioY+187,tp_symbol_color,InpFontSize,true);
   ScenarioLabel("tp_account_title","TP合計(口座)",label_end,InpScenarioY+210,tp_account_color,InpFontSize,true);
   ScenarioLabel("sl_title","SL合計(銘柄)",label_end,InpScenarioY+263,sl_symbol_color,InpFontSize,true);
   ScenarioLabel("sl_account_title","SL合計(口座)",label_end,InpScenarioY+286,sl_account_color,InpFontSize,true);
   for(int kind=0;kind<2;kind++)
   {
      bool tp=kind==0;
      int row=InpScenarioY+(tp ? 187 : 263);
      ScenarioLabel(tp ? "tp_delta_title" : "sl_delta_title",tp ? "TP差額" : "SL差額",label_end,row+46,
            clrWhite,InpFontSize,true);
      string key=tp ? "tp" : "sl";
      double other=tp ? other_tp : other_sl;
      bool other_ok=tp ? other_tp_ok : other_sl_ok;
      bool other_missing=tp ? other_tp_missing : other_sl_missing;
      bool trial_set=tp ? InpTrialTP>0 : InpTrialSL>0;
      int columns[3]={current,all,half};
      string suffixes[3]={"now","all","half"};
      for(int mode=0;mode<3;mode++)
      {
         string invalid=status[kind][mode];
         string account_invalid=(invalid=="未試算" ? invalid :
                                 (other_missing ? "未設定あり" : invalid));
         ScenarioCell(key+"_"+suffixes[mode],values[kind][mode],valid[kind][mode],currency,
                      columns[mode],row,invalid);
         ScenarioCell(key+"_account_"+suffixes[mode],other+values[kind][mode],
                      other_ok && valid[kind][mode],currency,columns[mode],row+23,
                      account_invalid);
      }
      ScenarioDeltaCell(key+"_all_delta",values[kind][1],valid[kind][1],
                        values[kind][0],valid[kind][0],currency,all,row+46,trial_set);
      ScenarioDeltaCell(key+"_half_delta",values[kind][2],valid[kind][2],
                        values[kind][0],valid[kind][0],currency,half,row+46,trial_set);
   }
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
   ArrayResize(scenario_label_names,0);
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
   bool other_tp_missing=false,other_sl_missing=false;
   if(!ScenarioSnapshot(positions,count,account_current,symbol_current,
                other_tp,other_sl,other_tp_ok,other_sl_ok,
                other_tp_missing,other_sl_missing))
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
   double all_lots=0,half_lots=0;
   for(int i=0;i<count;i++)
   {
      all_lots+=positions[i].lots;
      if(ranking_ok && selected[i]) half_lots+=positions[i].lots;
   }
   double values[2][3];
   bool valid[2][3];
   string status[2][3];
   bool current_tp_missing=false;
   for(int i=0;i<count;i++)
      if(positions[i].tp<=0) current_tp_missing=true;
   for(int kind=0;kind<2;kind++)
   {
      bool tp=kind==0;
      for(int mode=0;mode<3;mode++)
      {
         bool trial_set=tp ? InpTrialTP>0 : InpTrialSL>0;
         bool missing=ScenarioHasUnsetExit(positions,count,selected,tp,
                                            (mode==2 && !ranking_ok) ? 0 : mode);
         if(mode==2 && !ranking_ok && current_tp_missing) missing=true;
         status[kind][mode]=(mode>0 && !trial_set) ? "未試算" :
                            (missing ? "未設定あり" : "算出不可");
         values[kind][mode]=0;
         valid[kind][mode]=(mode!=2 || ranking_ok) &&
                           (mode==0 || trial_set) &&
                           ScenarioSumCase(positions,count,selected,tp,mode,values[kind][mode]);
      }
   }
   string currency=AccountInfoString(ACCOUNT_CURRENCY);
   ScenarioRender(count,ranking_ok,all_lots,half_lots,values,valid,status,
          other_tp_missing,other_sl_missing,
          account_current,symbol_current,other_tp,other_sl,other_tp_ok,other_sl_ok,currency);
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
   string symbol_value=ScenarioPanelPrefix()+"symbol_current_value";
   string account_value=ScenarioPanelPrefix()+"account_current_value";
   if(ObjectFind(0,symbol_name)<0 || ObjectFind(0,account_name)<0 ||
      ObjectFind(0,symbol_value)<0 || ObjectFind(0,account_value)<0) return;
   double symbol_profit=0;
   for(int i=0;i<PositionsTotal();i++)
   {
      if(PositionGetTicket(i)==0) return;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol)
         symbol_profit+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
   }
   double account_profit=AccountInfoDouble(ACCOUNT_PROFIT);
   string currency=AccountInfoString(ACCOUNT_CURRENCY);
   ObjectSetString(0,symbol_value,OBJPROP_TEXT,ScenarioSignedMoney(symbol_profit,currency));
   ObjectSetInteger(0,symbol_name,OBJPROP_COLOR,ScenarioAmountColor(symbol_profit));
   ObjectSetInteger(0,symbol_value,OBJPROP_COLOR,ScenarioAmountColor(symbol_profit));
   ObjectSetString(0,account_value,OBJPROP_TEXT,ScenarioSignedMoney(account_profit,currency));
   ObjectSetInteger(0,account_name,OBJPROP_COLOR,ScenarioAmountColor(account_profit));
   ObjectSetInteger(0,account_value,OBJPROP_COLOR,ScenarioAmountColor(account_profit));
   // Other indicators can recreate horizontal-line objects after this panel.
   // Requeue our objects in their original order so the opaque panel remains
   // above those lines without changing or hiding anyone else's chart objects.
   string background=ScenarioPanelPrefix()+"background";
   if(ObjectFind(0,background)>=0)
   {
      ObjectSetInteger(0,background,OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
      ObjectSetInteger(0,background,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
      for(int i=0;i<ArraySize(scenario_label_names);i++)
      {
         string name=scenario_label_names[i];
         ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
         ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
      }
   }
   ChartRedraw(0);
}
