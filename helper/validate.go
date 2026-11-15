package main

import (
	"fmt"
	"strings"
)

// validate accepts only the shape of config the mimray app generates.
// The core runs as root, so anything that could make it read or write files
// (log output, certificate/key paths, rule-set files, cache file, external UI,
// extra services/endpoints) or listen on a non-loopback address is rejected.
func validate(c map[string]any) error {
	if err := keysIn("config", c, "log", "dns", "inbounds", "outbounds", "route", "experimental"); err != nil {
		return err
	}

	if v, ok := c["log"]; ok {
		m, ok := v.(map[string]any)
		if !ok {
			return fmt.Errorf("log must be an object")
		}
		if err := keysIn("log", m, "level"); err != nil {
			return err
		}
	}

	ins, ok := c["inbounds"].([]any)
	if !ok || len(ins) != 1 {
		return fmt.Errorf("exactly one inbound (tun) required")
	}
	in, ok := ins[0].(map[string]any)
	if !ok || in["type"] != "tun" {
		return fmt.Errorf("inbound must be tun")
	}
	if err := keysIn("inbound", in, "type", "tag", "address", "auto_route", "strict_route", "stack", "mtu"); err != nil {
		return err
	}

	outs, ok := c["outbounds"].([]any)
	if !ok || len(outs) == 0 {
		return fmt.Errorf("outbounds required")
	}
	okTypes := set("vmess", "vless", "trojan", "shadowsocks", "hysteria2", "direct", "urltest", "selector")
	for i, o := range outs {
		m, ok := o.(map[string]any)
		if !ok {
			return fmt.Errorf("outbound %d must be an object", i)
		}
		t, _ := m["type"].(string)
		if !okTypes[t] {
			return fmt.Errorf("outbound type %q not allowed", t)
		}
		if err := noFileFields(fmt.Sprintf("outbounds[%d]", i), "", m); err != nil {
			return err
		}
	}

	if v, ok := c["dns"]; ok {
		d, ok := v.(map[string]any)
		if !ok {
			return fmt.Errorf("dns must be an object")
		}
		if err := keysIn("dns", d, "servers", "rules", "final", "strategy"); err != nil {
			return err
		}
		servers, _ := d["servers"].([]any)
		dnsTypes := set("https", "tls", "udp", "local", "fakeip")
		for i, s := range servers {
			m, ok := s.(map[string]any)
			if !ok {
				return fmt.Errorf("dns server %d must be an object", i)
			}
			if err := keysIn("dns.servers", m, "type", "tag", "server", "server_port", "detour", "inet4_range", "inet6_range"); err != nil {
				return err
			}
			if t, _ := m["type"].(string); !dnsTypes[t] {
				return fmt.Errorf("dns server type %q not allowed", t)
			}
		}
		dnsRules, _ := d["rules"].([]any)
		for i, x := range dnsRules {
			m, ok := x.(map[string]any)
			if !ok {
				return fmt.Errorf("dns rule %d must be an object", i)
			}
			if err := keysIn("dns.rules", m, "query_type", "server"); err != nil {
				return err
			}
		}
	}

	if v, ok := c["route"]; ok {
		r, ok := v.(map[string]any)
		if !ok {
			return fmt.Errorf("route must be an object")
		}
		if err := keysIn("route", r, "rules", "auto_detect_interface", "default_domain_resolver", "final"); err != nil {
			return err
		}
		rules, _ := r["rules"].([]any)
		actions := set("", "sniff", "hijack-dns", "reject", "route")
		for i, x := range rules {
			m, ok := x.(map[string]any)
			if !ok {
				return fmt.Errorf("rule %d must be an object", i)
			}
			if err := keysIn("route.rules", m, "action", "protocol", "network", "port", "domain", "domain_suffix", "ip_cidr", "ip_is_private", "outbound"); err != nil {
				return err
			}
			if a, _ := m["action"].(string); !actions[a] {
				return fmt.Errorf("rule action %q not allowed", a)
			}
		}
	}

	if v, ok := c["experimental"]; ok {
		e, ok := v.(map[string]any)
		if !ok {
			return fmt.Errorf("experimental must be an object")
		}
		if err := keysIn("experimental", e, "clash_api"); err != nil {
			return err
		}
		api, ok := e["clash_api"].(map[string]any)
		if !ok {
			return fmt.Errorf("clash_api must be an object")
		}
		if err := keysIn("clash_api", api, "external_controller", "secret"); err != nil {
			return err
		}
		if ctl, _ := api["external_controller"].(string); !strings.HasPrefix(ctl, "127.0.0.1:") {
			return fmt.Errorf("stats API must listen on 127.0.0.1")
		}
	}
	return nil
}

// noFileFields walks an outbound and rejects any field that names a file.
// "path" is only allowed as the HTTP path inside a transport (ws/http/httpupgrade).
func noFileFields(where, parent string, v any) error {
	switch x := v.(type) {
	case map[string]any:
		for k, child := range x {
			p := where + "." + k
			if strings.HasSuffix(k, "_path") || strings.HasSuffix(k, "_file") ||
				(k == "path" && parent != "transport") ||
				k == "directory" || k == "output" || k == "rule_set" {
				return fmt.Errorf("%s not allowed (file access)", p)
			}
			if err := noFileFields(p, k, child); err != nil {
				return err
			}
		}
	case []any:
		for i, child := range x {
			if err := noFileFields(fmt.Sprintf("%s[%d]", where, i), parent, child); err != nil {
				return err
			}
		}
	}
	return nil
}

func keysIn(where string, m map[string]any, allowed ...string) error {
	ok := set(allowed...)
	for k := range m {
		if !ok[k] {
			return fmt.Errorf("%s.%s not allowed", where, k)
		}
	}
	return nil
}

func set(xs ...string) map[string]bool {
	m := make(map[string]bool, len(xs))
	for _, x := range xs {
		m[x] = true
	}
	return m
}
