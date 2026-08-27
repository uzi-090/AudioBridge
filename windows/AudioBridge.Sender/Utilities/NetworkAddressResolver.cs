using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;

namespace AudioBridge.Sender.Utilities;

public static class NetworkAddressResolver
{
    public static string GetPreferredLocalAddress()
    {
        var candidates = new List<(IPAddress Address, int Score)>();
        foreach (var network in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (network.OperationalStatus != OperationalStatus.Up ||
                network.NetworkInterfaceType is NetworkInterfaceType.Loopback or NetworkInterfaceType.Tunnel)
            {
                continue;
            }

            var properties = network.GetIPProperties();
            var hasIpv4Gateway = properties.GatewayAddresses.Any(gateway =>
                gateway.Address.AddressFamily == AddressFamily.InterNetwork &&
                !gateway.Address.Equals(IPAddress.Any));
            var interfaceScore = network.NetworkInterfaceType switch
            {
                NetworkInterfaceType.Wireless80211 => 0,
                NetworkInterfaceType.Ethernet => 1,
                _ => 10,
            };

            foreach (var address in properties.UnicastAddresses
                         .Select(unicast => unicast.Address)
                         .Where(address => address.AddressFamily == AddressFamily.InterNetwork && !IPAddress.IsLoopback(address)))
            {
                var score = interfaceScore;
                if (!hasIpv4Gateway)
                {
                    score += 20;
                }
                if (!IsPrivateAddress(address))
                {
                    score += 5;
                }
                candidates.Add((address, score));
            }
        }

        return candidates.OrderBy(candidate => candidate.Score).FirstOrDefault().Address?.ToString()
            ?? "127.0.0.1";
    }

    private static bool IsPrivateAddress(IPAddress address)
    {
        var bytes = address.GetAddressBytes();
        return bytes[0] == 10 ||
            (bytes[0] == 172 && bytes[1] is >= 16 and <= 31) ||
            (bytes[0] == 192 && bytes[1] == 168);
    }
}
