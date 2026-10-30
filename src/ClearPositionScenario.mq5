// Removes only the chart objects created by PositionScenario on this chart.
// No orders, positions, or TP/SL are changed.
#property description "Clear the PositionScenario result from this chart."

void OnStart()
{
   int removed=ObjectsDeleteAll(0,"PositionScenario_");
   ChartRedraw(0);
   PrintFormat("ClearPositionScenario: removed %d display objects from chart %I64d.",
               removed,ChartID());
}
