#!/usr/bin/env python
import sys, json, ipaddress

def main():
    try:
        input_data = json.load(sys.stdin)
        ipv6 = ipaddress.IPv6Address(input_data["ipv6"])
        # Expand and remove leading zeroes (but keep hex format)
        expanded = ':'.join(part.lstrip('0') or '0' for part in ipv6.exploded.split(':'))
        print(json.dumps({"expanded": expanded}))
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)


if __name__ == "__main__":
    main()


