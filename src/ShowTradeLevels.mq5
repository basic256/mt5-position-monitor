// Restores MT5's built-in trade level display on the current chart only.
// Does not place or modify orders, positions, Stop Loss or Take Profit.
#property description "Show MT5 position, Stop Loss and Take Profit levels on this chart."

void OnStart()
{
   bool before=(bool)ChartGetInteger(0,CHART_SHOW_TRADE_LEVELS);
   bool changed=ChartSetInteger(0,CHART_SHOW_TRADE_LEVELS,true);
   ChartRedraw(0);
   bool after=(bool)ChartGetInteger(0,CHART_SHOW_TRADE_LEVELS);
   PrintFormat("ShowTradeLevels: chart=%I64d symbol=%s before=%d set_ok=%d after=%d",
               ChartID(),_Symbol,(int)before,(int)changed,(int)after);
}
