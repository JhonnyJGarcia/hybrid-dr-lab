# Phase 2: Site-to-site VPN

IPsec tunnel between **OPNsense** at home and an **Azure VPN Gateway**. Built by hand in the portal first (ClickOps), with the generated ARM template saved for comparison with Terraform later.

```
 Home LAN ── OPNsense ── ISP router (NAT) ── internet ── Azure VPN Gateway ── VNet 10.50.0.0/16
             (initiator,                                  (Basic SKU,
              route-based VTI)                             route-based)
```

## Azure side

| Resource | Name | Notes |
|---|---|---|
| VPN gateway | `vpng-dr-lab-sdc` | **Basic** SKU, route-based, in `GatewaySubnet` (`10.50.0.0/27`) |
| Public IP | `pip-vpng-dr-lab-sdc` | Standard, static |
| Local network gateway | home site | Home public IP (static) and **only the home lab network** as address space |
| Connection | S2S, IPsec | Pre-shared key, default IPsec policy |

**Why Basic:** ~0.036 USD/h (~26 USD/month) against ~0.19 USD/h (~139 USD/month) for VpnGw1. It supports route-based IKEv2, which is all the lab needs. Its limit is that **custom IPsec/IKE policies are not supported**: the home side has to match Azure's defaults.

**Why only the lab network in the local network gateway:** Azure routes exactly those prefixes into the tunnel. Advertising more (the remote-access VPN range, other home LANs) would widen what Azure can reach for no benefit.

## OPNsense side

- **Route-based** tunnel with a **VTI** interface (assigned as an interface so it gets its own firewall rules), inner addresses on `169.254.0.0/30`
- Child SA: policies **off**, `0.0.0.0/0 ↔ 0.0.0.0/0`, reqid 1, PFS none, start action *start*
- Static route `10.50.0.0/16` via the VTI interface
- Firewall rule on the VTI interface: Azure VNet → home lab network
- Dead peer detection on

**Behind NAT:** OPNsense sits behind the ISP router. Because OPNsense is the **initiator** and NAT-T moves IPsec to UDP 4500, **no port forward** on the ISP router was needed.

## Result

Azure connection status **Connected**, phase 1 and phase 2 SAs installed on OPNsense, traffic flowing both ways.

## Issues found and fixes

The tunnel failed with `NO_PROPOSAL_CHOSEN` and address mismatches until three settings were right. All three were configuration mix-ups worth writing down:

| Setting | Wrong | Right |
|---|---|---|
| Connection *local address* | The home **public** IP | OPNsense's **WAN private IP** (or `%defaultroute`). The public IP goes only in the **local authentication ID**, because that is what Azure expects to see after NAT |
| Connection *remote address* | Azure's internal gateway IP in the VNet | Azure's **public** IP. The internal address only appears in the static route |
| Phase 1 proposals | strongSwan *default* | Must include **DH group 2 (modp1024)**. strongSwan's default set leaves it out as weak, but Basic SKU's default policy requires it, and Basic cannot be given a custom policy |

DH group 2 is weak by today's standards. It is accepted here because the lab is short-lived and Basic SKU leaves no choice; a production setup would use VpnGw1 or higher with a custom IPsec policy (e.g. DH group 14/24, AES-GCM).

## Open item

- **MSS clamping** (1300) on the VTI interface, to avoid fragmentation and stalled TCP sessions through the tunnel.
