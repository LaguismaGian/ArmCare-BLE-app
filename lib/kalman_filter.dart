class KalmanFilter {
  double Q;
  double R;
  double P;
  double K;
  double X;

  KalmanFilter({this.Q = 0.1, this.R = 1.0})
      : P = 1.0,
        K = 0.0,
        X = 0.0;

  double update(double measurement) {
    P = P + Q;
    K = P / (P + R);
    X = X + K * (measurement - X);
    P = (1 - K) * P;
    return X;
  }
}