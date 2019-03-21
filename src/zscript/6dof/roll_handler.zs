class RollHandler : EventHandler
{
    const rollAmount = 4 * 65536.0 / 360;

    int roll;

    override void UiTick()
    {
        players[consolePlayer].cmd.roll = roll;
    }

    override void NetworkProcess(ConsoleEvent e)
    {
        if (e.name ~== "+rollleft") roll = -rollAmount;
        else if (e.name ~== "-rollleft") roll = 0;
        else if (e.name ~== "+rollright") roll = rollAmount;
        else if (e.name ~== "-rollright") roll = 0;
    }
}