{ dashboardCount, ... }:
{
  custom = {
    name = "synthetic-replacement";
    rules = [
      {
        alert = "SyntheticInventory";
        expr = "vector(${toString dashboardCount}) == 0";
      }
    ];
  };
}
