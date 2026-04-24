sealed class AuthState {
  const AuthState();
}

class Unauthenticated extends AuthState {
  const Unauthenticated();
}

class Authenticated extends AuthState {
  const Authenticated({required this.userId, required this.email});
  final String userId;
  final String email;
}

class AuthChecking extends AuthState {
  const AuthChecking();
}
