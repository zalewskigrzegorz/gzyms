public enum RestartRoute: Equatable, Sendable { case kickstart, relaunch }

/// kickstart only when launchd's `dev.gzyms` runs this very binary (paths already resolved). For any other copy,
/// a build from the tap above all, it would restart the wrong one or nothing.
public func restartRoute(agentProgram: String?, me: String?) -> RestartRoute {
    agentProgram != nil && agentProgram == me ? .kickstart : .relaunch
}

/// `/bin/sh` arguments that open the bundle again once `pid` is gone: the new copy would lose the InstanceLock
/// to the old one still quitting. Gives up waiting after 10 s. The path goes in as $0, so no quoting.
public func relaunchArguments(pid: Int32, bundle: String) -> [String] {
    ["-c", "i=0; while kill -0 \(pid) 2>/dev/null && [ $i -lt 100 ]; do sleep 0.1; i=$((i+1)); done; open -n \"$0\"", bundle]
}
