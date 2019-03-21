version "3.7.2"


struct Quaternion
{
    double w;
    Vector3 v;

    void Copy(in Quaternion other)
    {
        w = other.w;
        v = other.v;
    }

    void FromEulerAngle(double yaw, double pitch, double roll)
    {
        double cy = Cos(yaw * 0.5);
        double sy = Sin(yaw * 0.5);
        double cp = Cos(pitch * 0.5);
        double sp = Sin(pitch * 0.5);
        double cr = Cos(roll * 0.5);
        double sr = Sin(roll * 0.5);

        w = cy * cp * cr + sy * sp * sr;
        v.x = cy * cp * sr - sy * sp * cr;
        v.y = sy * cp * sr + cy * sp * cr;
        v.z = sy * cp * cr - cy * sp * sr;
    }

    float, float, float ToEulerAngle()
    {
        // Roll
        double sinRCosP = 2 * (w * v.x + v.y * v.z);
        double cosRCosP = 1 - 2 * (v.x * v.x + v.y * v.y);
        double roll = Atan2(sinRCosP, cosRCosP);

        // Pitch
        double sinP = 2 * (w * v.y - v.z * v.x);
        double pitch;
        if (Abs(sinP) >= 1) pitch = 90 * (sinP < 0 ? -1 : 1);
        else pitch = Asin(sinP);

        // Yaw
        double sinYCosP = 2 * (w * v.z + v.x * v.y);
        double cosYCosP = 1 - 2 * (v.y * v.y + v.z * v.z);
        double yaw = Atan2(sinYCosP, cosYCosP);

        return yaw, pitch, roll;
    }

    void Invert()
    {
        v = -v;
    }

    Vector3 Rotate(Vector3 v)
    {
        Quaternion v4;
        v4.v = v;

        Invert();
        Multiply(v4, v4, self);
        Invert();
        Multiply(v4, self, v4);

        return v4.v;
    }

    static void Add(out Quaternion res, in Quaternion lhs, in Quaternion rhs)
    {
        res.w = lhs.w + rhs.w;
        res.v = lhs.v + rhs.v;
    }

    static void Subtract(out Quaternion res, in Quaternion lhs, in Quaternion rhs)
    {
        res.w = lhs.w - rhs.w;
        res.v = lhs.v - rhs.v;
    }

    static void Scale(out Quaternion res, in double lhs, in Quaternion rhs)
    {
        res.w = lhs * rhs.w;
        res.v = lhs * rhs.v;
    }

    static void Multiply(out Quaternion res, in Quaternion lhs, in Quaternion rhs)
    {
        double lw = lhs.w;
        double rw = rhs.w;

        res.w = rw * lw - rhs.v dot lhs.v;
        res.v = rw * lhs.v + lw * rhs.v + lhs.v cross rhs.v;
    }

    static double DotProduct(in Quaternion lhs, in Quaternion rhs)
    {
        return lhs.w * rhs.w + lhs.v dot rhs.v;
    }

    static void Slerp(out Quaternion res, in Quaternion start, in Quaternion end, double t)
    {
        Quaternion s;
        s.Copy(start);
        Quaternion e;
        e.Copy(end);

        double dp = DotProduct(s, e);

        if (dp < 0)
        {
            Scale(e, -1, e);
            dp *= -1;
        }

        if (dp > 0.9995)
        {
            Subtract(res, e, s);
            Scale(res, t, res);
            Add(res, s, res);
        }
        else
        {
            double theta0 = ACos(dp);
            double theta = t * theta0;
            double sinTheta = Sin(theta);
            double sinTheta0 = Sin(Theta0);

            Scale(s, Cos(theta) - dp * sinTheta / sinTheta0, s);
            Scale(e, sinTheta / sinTheta0, e);
            Add(res, s, e);
        }
    }
}


class SixDoFPlayer : DoomPlayer
{
    Property UpMove : upMove;


    Default
    {
        Speed 320 / ticRate;
        SixDoFPlayer.UpMove 1.0;

        +NoGravity
        +RollSprite
    }


    const maxYaw = 65536.0;
    const maxPitch = 65536.0;
    const maxRoll = 65536.0;
    const maxForwardMove = 12800;
    const maxSideMove = 10240;
    const maxUpMove = 768;
    const stopFlying = -32768;

    const trichordingCVar = "G_Trichording";


    double upMove;
    Quaternion targetRotation;


    override void PostBeginPlay()
    {
        Super.PostBeginPlay();

        bFly = true;
        targetRotation.FromEulerAngle(angle, pitch, roll);
    }


    override void HandleMovement()
    {
        if (reactionTime) --reactionTime;   // Player is frozen
        else
        {
            CheckQuickTurn();
            RotatePlayer();
            MovePlayer();
        }
    }


    override void CheckCrouch(bool totallyFrozen) {}
    override void CheckPitch() {}


    override void MovePlayer()
    {
        UserCmd cmd = player.cmd;

        if (IsPressed(BT_Jump)) cmd.upMove = maxUpMove;
        if (IsPressed(BT_Crouch)) cmd.upMove = -maxUpMove;
        if (cmd.upMove == stopFlying) cmd.upMove = 0;   // Can't stop flying

        if (cmd.forwardMove || cmd.sideMove || cmd.upMove)
        {
            double scale = CmdScale();
            double fm = scale * cmd.forwardMove / maxForwardMove;
            double sm = scale * cmd.sideMove / maxSideMove;
            double um = scale * cmd.upMove / maxUpMove;

            [fm, sm, um] = TweakSpeeds3(fm, sm, um);

            Vector3 forward, right, up;
            [forward, right, up] = GetAxes();

            Vector3 wishVel = fm * forward + sm * right + um * up;

            Accelerate(wishVel.Unit(), wishVel.Length(), 4.0);
            BobAccelerate(wishVel.Unit(), wishVel.Length(), 4.0);

            if (!(player.cheats & CF_PREDICTING)) PlayRunning();

			if (player.cheats & CF_REVERTPLEASE)
			{
				player.cheats &= ~CF_REVERTPLEASE;
				player.camera = player.mo;
			}
        }
    }


    virtual void CheckQuickTurn()
    {
        UserCmd cmd = player.cmd;

		if (JustPressed(BT_Turn180)) player.turnticks = turn180_ticks;

        if (player.turnTicks)
        {
            --player.turnTicks;
            cmd.yaw = 0.5 * maxYaw / turn180_ticks;
        }
    }


    virtual void RotatePlayer()
    {
        // Find target rotation
        UserCmd cmd = player.cmd;
        double cmdYaw = cmd.yaw * 360 / maxYaw;
        double cmdPitch = -cmd.pitch * 360 / maxPitch;
        double cmdRoll = cmd.roll * 360 / maxRoll;

        Quaternion input;
        input.FromEulerAngle(cmdYaw, cmdPitch, cmdRoll);
        Quaternion.Multiply(targetRotation, targetRotation, input);

        // Interpolate to it
        Quaternion r;
        r.FromEulerAngle(angle, pitch, roll);

        Quaternion.Slerp(r, r, targetRotation, 0.2);

        double newAngle, newPitch, newRoll;
        [newAngle, newPitch, newRoll] = r.ToEulerAngle();

        A_SetAngle(newAngle, SPF_Interpolate);
        A_SetPitch(newPitch, SPF_Interpolate);
        A_SetRoll(newRoll, SPF_Interpolate);
    }


    virtual double, double, double TweakSpeeds3(double forward, double side, double up)
    {
        [forward, side] = TweakSpeeds(forward, side);

        up *= upMove;

        return forward, side, up;
    }


    virtual double CmdScale()
    {
        bool canStraferun = CVar.FindCVar(trichordingCVar).GetBool();
        if (canStraferun) return speed;

		UserCmd cmd = player.cmd;
        double fm = double(cmd.forwardMove) / maxForwardMove;
        double sm = double(cmd.sideMove) / maxSideMove;
        double um = double(cmd.upMove) / maxUpMove;

        double maxCmd = Max(Abs(fm), Abs(sm), Abs(um));
        double total = (fm, sm, um).Length();

        double scale = total ? speed * maxCmd / total : 0;

        return scale;
    }


    virtual void Accelerate(Vector3 wishDir, double wishSpeed, double accel)
    {
        double currentSpeed = vel dot wishDir;

        double addSpeed = wishSpeed - currentSpeed;
        if (addSpeed <= 0) return;

        double accelSpeed = Min(accel * wishSpeed, addSpeed);

        vel += accelSpeed * wishDir;
    }


    virtual void BobAccelerate(Vector3 wishDir, double wishSpeed, double accel)
    {
        double currentSpeed = player.vel dot wishDir.xy;

        double addSpeed = wishSpeed - currentSpeed;
        if (addSpeed <= 0) return;

        double accelSpeed = Clamp(accel * wishSpeed, 0, addSpeed);

        player.vel += accelSpeed * wishDir.xy;
    }


    Vector3, Vector3, Vector3 GetAxes()
    {
        Quaternion r;
        r.FromEulerAngle(angle, pitch, roll);

        Vector3 forward = (1, 0, 0);
        forward = r.Rotate(forward);

        Vector3 right = (0, -1, 0);
        right = r.Rotate(right);

        Vector3 up = (0, 0, 1);
        up = r.Rotate(up);

        return forward, right, up;
    }


    bool IsPressed(int bt)
    {
        return player.cmd.buttons & bt;
    }

    bool JustPressed(int bt)
    {
        return (player.cmd.buttons & bt) && !(player.oldButtons & bt);
    }
}


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