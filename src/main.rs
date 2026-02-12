use std::{
    io::{self},
    net::{IpAddr, ToSocketAddrs},
};

/// Command-line interface of mydns.
fn main() {
    let mut args = std::env::args();
    args.next(); // Skip program name argument
    let host = args.next().expect("argument must be provided");
    if args.next().is_some() {
        panic!("Too many arguments!");
    }
    let ip_list = get_ip_list_for_host(&host).expect("should get IP list for host");
    if ip_list.is_empty() {
        eprintln!("No IPs found!");
    } else {
        for ip in ip_list {
            println!("{ip}");
        }
    }
}

/// Given a host, return the list of IP address that it resolves to.
fn get_ip_list_for_host(host: &str) -> io::Result<Vec<IpAddr>> {
    let socket_addrs = (host, 443).to_socket_addrs()?;
    Ok(socket_addrs.map(|addr| addr.ip()).collect())
}

#[cfg(test)]
mod mydns_tests {
    use std::net::{IpAddr, Ipv4Addr};

    use crate::get_ip_list_for_host;

    #[test]
    /// Test that an IP address returns itself.
    fn local_ip() {
        assert_eq!(
            get_ip_list_for_host("127.0.0.1").unwrap(),
            vec![IpAddr::V4(Ipv4Addr::new(127, 0, 0, 1))],
        );
    }

    #[test]
    /// Test that a nip.io subdomain (which resolves to itself)
    /// returns the expected address.
    fn ip_for_nip_io() {
        assert_eq!(
            get_ip_list_for_host("52-0-56-137.nip.io").unwrap(),
            vec![IpAddr::V4(Ipv4Addr::new(52, 0, 56, 137))],
        );
    }
}
