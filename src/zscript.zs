version "3.7.2"


struct Quaternion
{
    double w, x, y, z;

    void Copy(in Quaternion other)
    {
        w = other.w;
        x = other.x;
        y = other.y;
        z = other.z;
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
        x = cy * cp * sr - sy * sp * cr;
        y = sy * cp * sr + cy * sp * cr;
        z = sy * cp * cr - cy * sp * sr;
    }

    float, float, float ToEulerAngle()
    {
        // Roll
        double sinRCosP = 2 * (w * x + y * z);
        double cosRCosP = 1 - 2 * (x * x + y * y);
        double roll = Atan2(sinRCosP, cosRCosP);

        // Pitch
        double sinP = 2 * (w * y - z * x);
        double pitch;
        if (Abs(sinP) >= 1) pitch = 90 * (sinP < 0 ? -1 : 1);
        else pitch = Asin(sinP);

        // Yaw
        double sinYCosP = 2 * (w * z + x * y);
        double cosYCosP = 1 - 2 * (y * y + z * z);
        double yaw = Atan2(sinYCosP, cosYCosP);

        return yaw, pitch, roll;
    }

    void SetXyz(Vector3 v)
    {
        x = v.x;
        y = v.y;
        z = v.z;
    }

    Vector3 GetXyz()
    {
        return (x, y, z);
    }

    void Invert()
    {
        x *= -1;
        y *= -1;
        z *= -1;
    }

    Vector3 Rotate(Vector3 v)
    {
        Quaternion v4;
        v4.SetXyz(v);

        Invert();
        Multiply(v4, v4, self);
        Invert();
        Multiply(v4, self, v4);

        return v4.GetXyz();
    }

    static void Add(out Quaternion q, in Quaternion r, in Quaternion s)
    {
        q.w = r.w + s.w;
        q.x = r.x + s.x;
        q.y = r.y + s.y;
        q.z = r.z + s.z;
    }

    static void Sub(out Quaternion q, in Quaternion r, in Quaternion s)
    {
        q.w = r.w - s.w;
        q.x = r.x - s.x;
        q.y = r.y - s.y;
        q.z = r.z - s.z;
    }

    static void Scale(out Quaternion q, in double a, in Quaternion r)
    {
        q.w = a * r.w;
        q.x = a * r.x;
        q.y = a * r.y;
        q.z = a * r.z;
    }

    static void Multiply(out Quaternion q, in Quaternion r, in Quaternion s)
    {
        double rw = r.w;
        Vector3 rv = r.GetXyz();
        double sw = s.w;
        Vector3 sv = s.GetXyz();

        q.w = sw * rw - (sv dot rv);
        q.SetXyz(sw * rv + rw * sv + (rv cross sv));
    }

    static double DotProduct(in Quaternion q, in Quaternion r)
    {
        return q.w * r.w + q.x * r.x + q.y * r.y + q.z * r.z;
    }

    static void Slerp(out Quaternion q, in Quaternion r, in Quaternion s, double t)
    {
        Quaternion r2;
        r2.Copy(r);
        Quaternion s2;
        s2.Copy(s);

        double dp = DotProduct(r2, s2);

        if (dp < 0)
        {
            s2.w *= -1;
            s2.x *= -1;
            s2.y *= -1;
            s2.z *= -1;

            dp *= -1;
        }

        if (dp > 0.9995)
        {
            Sub(q, s2, r2);
            Scale(q, t, q);
            Add(q, r2, q);
        }
        else
        {
            double theta0 = ACos(dp);
            double theta = t * theta0;
            double sinTheta = Sin(theta);
            double sinTheta0 = Sin(Theta0);

            double sr = Cos(theta) - dp * sinTheta / sinTheta0;
            double ss = sinTheta / sinTheta0;

            Scale(r2, sr, r2);
            Scale(s2, ss, s2);
            Add(q, r2, s2);
        }
    }
}


class FlyingPlayer : DoomPlayer
{
    Property UpMove : upMove;


    Default
    {
        Speed 320 / ticRate;
        FlyingPlayer.UpMove 1.0;

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