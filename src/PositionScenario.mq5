// Read-only, one-shot TP/SL comparison. No order or position modification.
#property script_show_inputs
#property description "Preview TP/SL outcomes for all or half of the current symbol positions."

input double InpTrialTP=0.0;                 // 仮TP価格（0=試算しない）
input double InpTrialSL=0.0;                 // 仮SL価格（0=試算しない）
input bool InpIncludeSwap=true;             // 発生済みスワップを含める
input double InpExitCommissionPerLot=0.0;   // 決済手数料/lot（片道・口座通貨）
input bool InpClearResult=false;            // 前回の表示を消すだけ
input int InpX=15;                          // 右端からの距離 px
input int InpY=25;                          // 上端からの距離 px
input int InpFontSize=11;                   // フォントサイズ

struct PositionSnapshot
{
   ulong ticket;
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
   if(!OrderCalcProfit(side,_Symbol,position.lots,position.entry,exit_price,gross))
      return false;
   result=gross+(InpIncludeSwap ? position.swap : 0.0)-InpExitCommissionPerLot*position.lots;
   return MathIsValidNumber(result);
}

bool Snapshot(PositionSnapshot &positions[],int &count)
{
   count=0;
   int before=PositionsTotal();
   ArrayResize(positions,before);
   for(int i=0;i<before;i++)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) return false;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      positions[count].ticket=ticket;
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
   return PositionsTotal()==before;
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
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,right ? ANCHOR_RIGHT_UPPER : ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,size);
   ObjectSetInteger(0,name,OBJPROP_COLOR,colour);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}

void Cell(const string key,const double value,const bool valid,const string currency,
          const int right_distance,const int y)
{
   Label(key,valid ? SignedMoney(value,currency) : "算出不可",right_distance,y,
         valid ? AmountColor(value) : clrOrange,InpFontSize,true);
}

void DeltaCell(const string key,const double scenario,const bool scenario_ok,
               const double current,const bool current_ok,const string currency,
               const int right_distance,const int y)
{
   if(!scenario_ok || !current_ok)
   {
      Label(key,"差額 ―",right_distance,y,clrSilver,InpFontSize-1,true);
      return;
   }
   double difference=scenario-current;
   Label(key,"差額 "+SignedMoney(difference,currency),right_distance,y,
         AmountColor(difference),InpFontSize-1,true);
}

void Render(const int count,const bool ranking_ok,
            const double &values[][3],const bool &valid[][3],const string currency)
{
   const int width=665;
   const int height=235;
   string panel=Prefix()+"background";
   if(ObjectCreate(0,panel,OBJ_RECTANGLE_LABEL,0,0,0))
   {
      ObjectSetInteger(0,panel,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
      ObjectSetInteger(0,panel,OBJPROP_XDISTANCE,InpX);
      ObjectSetInteger(0,panel,OBJPROP_YDISTANCE,InpY);
      ObjectSetInteger(0,panel,OBJPROP_XSIZE,width);
      ObjectSetInteger(0,panel,OBJPROP_YSIZE,height);
      ObjectSetInteger(0,panel,OBJPROP_BGCOLOR,C'22,24,29');
      ObjectSetInteger(0,panel,OBJPROP_COLOR,C'90,95,103');
      ObjectSetInteger(0,panel,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,panel,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,panel,OBJPROP_BACK,false);
   }
   int left=InpX+width-16;
   int condition=InpX+width-123;
   int current=InpX+width-278;
   int all=InpX+width-462;
   int half=InpX+width-648;
   Label("title","Position Scenario  |  "+_Symbol+"  |  "+IntegerToString(count)+"件 / 半数"+
         IntegerToString(count/2)+"件",left,InpY+11,clrWhite,InpFontSize+1);
   Label("timestamp","試算時刻 "+TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS)+
         "  /  口座通貨 "+currency,left,InpY+36,clrSilver,InpFontSize-1);
   Label("h_current","現状",current,InpY+63,clrWhite,InpFontSize,true);
   Label("h_all","全件変更",all,InpY+63,clrWhite,InpFontSize,true);
   Label("h_half","半数変更",half,InpY+63,clrWhite,InpFontSize,true);
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   Label("tp_title",InpTrialTP>0 ? "TP "+Grouped(InpTrialTP,digits) : "TP 未入力",
         condition,InpY+90,clrLimeGreen,InpFontSize,true);
   Label("sl_title",InpTrialSL>0 ? "SL "+Grouped(InpTrialSL,digits) : "SL 未入力",
         condition,InpY+143,clrTomato,InpFontSize,true);
   Cell("tp_now",values[0][0],valid[0][0],currency,current,InpY+90);
   Cell("tp_all",values[0][1],valid[0][1],currency,all,InpY+90);
   Cell("tp_half",values[0][2],valid[0][2],currency,half,InpY+90);
   Cell("sl_now",values[1][0],valid[1][0],currency,current,InpY+143);
   Cell("sl_all",values[1][1],valid[1][1],currency,all,InpY+143);
   Cell("sl_half",values[1][2],valid[1][2],currency,half,InpY+143);
   DeltaCell("tp_all_delta",values[0][1],valid[0][1],values[0][0],valid[0][0],currency,all,InpY+113);
   DeltaCell("tp_half_delta",values[0][2],valid[0][2],values[0][0],valid[0][0],currency,half,InpY+113);
   DeltaCell("sl_all_delta",values[1][1],valid[1][1],values[1][0],valid[1][0],currency,all,InpY+166);
   DeltaCell("sl_half_delta",values[1][2],valid[1][2],values[1][0],valid[1][0],currency,half,InpY+166);
   string rule=ranking_ok ? "半数は現在TPの見込利益が低い順（奇数件は切り捨て）" :
                           "半数の選択不可：現在TPが未設定、または損益を計算できません";
   Label("rule",rule,left,InpY+193,ranking_ok ? clrSilver : clrOrange,InpFontSize-1);
   Label("note",InpIncludeSwap ? "発生済スワップ込  |  仮価格での見積り  |  実際のTP/SLは変更しません" :
                              "スワップ除外  |  仮価格での見積り  |  実際のTP/SLは変更しません",
         left,InpY+214,clrSilver,InpFontSize-1);
   ChartRedraw(0);
}

void ShowMessage(const string message)
{
   Label("message",message,InpX+640,InpY+20,clrOrange,InpFontSize);
   ChartRedraw(0);
   Print("PositionScenario: "+message);
}

void OnStart()
{
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
   if(!Snapshot(positions,count))
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
   Render(count,ranking_ok,values,valid,currency);
   PrintFormat("PositionScenario: %s %d positions, half %d. No orders or positions modified.",
               _Symbol,count,count/2);
}
