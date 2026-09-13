enum HomeRoleStatus {
  notHome,
  alreadyHome,
  requestStarted,
  settingsOpened,
  denied,
  unavailable,
  failed,
}

HomeRoleStatus statusAfterResume({
  required HomeRoleStatus previous,
  required bool isCurrentHome,
}) {
  if (isCurrentHome) return HomeRoleStatus.alreadyHome;
  if (previous == HomeRoleStatus.requestStarted ||
      previous == HomeRoleStatus.settingsOpened) {
    return HomeRoleStatus.denied;
  }
  if (previous == HomeRoleStatus.failed ||
      previous == HomeRoleStatus.unavailable) {
    return previous;
  }
  return HomeRoleStatus.notHome;
}
