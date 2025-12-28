##################################  Route 53 Private Hosted Zone  ##################################

# Create private hosted zone for your custom domain
resource "aws_route53_zone" "private" {
  name = "fast-api.local"

  vpc {
    vpc_id = data.aws_vpc.default_vpc.id
  }

  tags = {
    Name = "fast-api-private-zone"
  }
}

# Create CNAME record pointing custom domain to VPC Lattice DNS
resource "aws_route53_record" "service_a" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "service-a.fast-api.local"
  type    = "CNAME"
  ttl     = 300
  records = [aws_vpclattice_service.service_a.dns_entry[0].domain_name]
}

resource "aws_route53_record" "service_b" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "service-b.fast-api.local"
  type    = "CNAME"
  ttl     = 300
  records = [aws_vpclattice_service.service_b.dns_entry[0].domain_name]
}

# Output the nameservers (for verification)
output "route53_nameservers" {
  description = "Private hosted zone nameservers"
  value       = aws_route53_zone.private.name_servers
}

output "custom_domain_service_a" {
  description = "Service A custom domain (now resolvable)"
  value       = "https://service-a.fast-api.local"
}

output "custom_domain_service_b" {
  description = "Service B custom domain (now resolvable)"
  value       = "https://service-b.fast-api.local"
}