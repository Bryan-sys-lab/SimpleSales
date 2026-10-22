/// What happened when the app tried to renew a signed-in session.
///
/// The distinction this type exists for is the difference between "this
/// session is over" and "we could not ask". A till that loses signal for two
/// seconds is not the same as a till whose credentials were refused, and
/// treating them the same signs the cashier out of a shop that is still
/// trading.
///
/// Before this type existed, a refresh failure was one `false`, and every
/// failure cleared the stored session. A dead battery and a revoked password
/// produced the same result: the next person at the till was asked to sign in
/// again, with no way to know whether that was the app's fault or theirs.
sealed class SessionRenewal {
  const SessionRenewal();
}

/// A new session was issued. The tokens are in storage; read them from there.
final class SessionRenewed extends SessionRenewal {
  const SessionRenewed();
}

/// The server said, definitively, that this session is finished.
///
/// This is the ONLY outcome that may clear stored credentials. It means the
/// server looked at the token and refused it — an expired refresh token, a
/// revoked session, a token from a session that was signed out elsewhere.
final class SessionRejected extends SessionRenewal {
  const SessionRejected();
}

/// The attempt could not be completed: no network, a timeout, a 5xx.
///
/// The session may well still be good. It simply could not be renewed right
/// now, and nothing about it is known to be bad. Nothing is cleared.
final class SessionUnreachable extends SessionRenewal {
  const SessionUnreachable();
}

/// There is no session of this kind to renew.
///
/// The till never had a browser session, or a device session. Not a failure and
/// not a rejection: there was simply nothing to work with.
final class SessionAbsent extends SessionRenewal {
  const SessionAbsent();
}
