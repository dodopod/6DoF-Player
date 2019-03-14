version "3.7.2"


struct Quaternion
{
    double w, x, y, z;

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

    static void Multiply(out Quaternion q, in Quaternion r, in Quaternion s)
    {
        double rw = r.w;
        Vector3 rv = r.GetXyz();
        double sw = s.w;
        Vector3 sv = s.GetXyz();

        q.w = sw * rw - (sv dot rv);
        q.SetXyz(sw * rv + rw * sv + (rv cross sv));
    }
}


class FlyingPlayer : DoomPlayer
{
    const cmdScale = 360.0 / 65536;

    override void HandleMovement()
    {
        RotatePlayer();
    }

    override void CheckPitch() {}

    void RotatePlayer()
    {
        Quaternion r;
        r.FromEulerAngle(angle, pitch, roll);

        UserCmd cmd = player.cmd;
        double cmdYaw = cmd.yaw * cmdScale;
        double cmdPitch = -cmd.pitch * cmdScale;
        double cmdRoll = cmd.roll * cmdScale;

        Quaternion s;
        s.FromEulerAngle(cmdYaw, cmdPitch, cmdRoll);
        Quaternion.multiply(r, r, s);

        double newAngle, newPitch, newRoll;
        [newAngle, newPitch, newRoll] = r.ToEulerAngle();

        A_SetAngle(newAngle, SPF_Interpolate);
        A_SetPitch(newPitch, SPF_Interpolate);
        A_SetRoll(newRoll, SPF_Interpolate);
    }
}