local M = {}

M.directives = {
  ['@def'] = true, ['@include'] = true, ['@if'] = true, ['@else'] = true,
  ['@hook'] = true, ['@subchain'] = true, ['@gotosubchain'] = true, ['@preserve'] = true,
}

M.builtin_functions = {
  ['@defined'] = true, ['@eq'] = true, ['@ne'] = true, ['@not'] = true,
  ['@resolve'] = true, ['@cat'] = true, ['@join'] = true, ['@substr'] = true,
  ['@length'] = true, ['@basename'] = true, ['@dirname'] = true, ['@glob'] = true,
  ['@ipfilter'] = true,
}

M.location_keywords = {
  domain = true, table = true, chain = true, policy = true,
}

M.match_keywords = {
  protocol = true, proto = true, interface = true, outerface = true,
  saddr = true, daddr = true, sport = true, dport = true,
  sports = true, dports = true, module = true, mod = true,
  fragment = true, syn = true,
  ['if'] = true,
}

M.module_names = {
  account = true, addrtype = true, ah = true, bpf = true, cgroup = true,
  cluster = true, comment = true, connbytes = true, connlabel = true,
  connlimit = true, connmark = true, conntrack = true, cpu = true,
  dccp = true, devgroup = true, dscp = true, dst = true, ecn = true,
  esp = true, eui64 = true, frag = true, fuzzy = true, geoip = true,
  hashlimit = true, hbh = true, helper = true, hl = true, icmp = true,
  iprange = true, ipv4options = true, ipv6header = true, ipvs = true,
  length = true, limit = true, mac = true, mark = true, mh = true,
  multiport = true, nth = true, nfacct = true, osf = true, owner = true,
  pkttype = true, physdev = true, policy = true, psd = true, quota = true,
  rateest = true, realm = true, recent = true, rpfilter = true, rt = true,
  sctp = true, set = true, socket = true, state = true, statistic = true,
  string = true, tcp = true, tcpmss = true, time = true, tos = true,
  ttl = true, u32 = true, udp = true, unclean = true,
}

M.builtin_chains = {
  INPUT = true, OUTPUT = true, FORWARD = true, PREROUTING = true, POSTROUTING = true,
}

M.tables_set = {
  filter = true, nat = true, mangle = true, raw = true, security = true,
}

M.domains_set = {
  ip = true, ip6 = true, arp = true, eb = true,
}

M.targets = {
  ACCEPT = true, DROP = true, REJECT = true, RETURN = true, NOP = true,
  LOG = true, ULOG = true, NFLOG = true,
  DNAT = true, SNAT = true, MASQUERADE = true, REDIRECT = true, NETMAP = true,
  MARK = true, CONNMARK = true, TCPMSS = true, TOS = true, DSCP = true,
  TTL = true, HL = true, CLASSIFY = true, IDLETIMER = true, LED = true,
  NFQUEUE = true, NOTRACK = true, RATEEST = true, SECMARK = true,
  CONNSECMARK = true, SET = true, CT = true, TPROXY = true, TRACE = true,
  BALANCE = true, CLUSTERIP = true, CONNMARK_RESTORE = true, CONNMARK_SAVE = true,
  ECN = true, HMARK = true, IPMARK = true, MIRROR = true, SAME = true,
  SYNPROXY = true, AUDIT = true, CHECKSUM = true, DNPT = true, SNPT = true,
  RAWDNAT = true, RAWSNAT = true,
}

M.protocols = {
  tcp = true, udp = true, udplite = true, icmp = true, icmpv6 = true,
  esp = true, ah = true, gre = true, sctp = true, dccp = true, mh = true,
}

M.conntrack_states = {
  NEW = true, ESTABLISHED = true, RELATED = true, INVALID = true, UNTRACKED = true,
}

M.tcp_flags = {
  SYN = true, ACK = true, FIN = true, RST = true, URG = true, PSH = true, ALL = true, NONE = true,
}

M.module_params = {
  -- conntrack
  ctstate = true, ctstatus = true, ctproto = true, ctorigsrc = true, ctorigdst = true,
  ctreplsrc = true, ctrepldst = true, ctorigsrcport = true, ctorigdstport = true,
  ctreplsrcport = true, ctrepldstport = true, ctdir = true, ctexpire = true,
  -- log
  ['log-prefix'] = true, ['log-level'] = true, ['log-ip-options'] = true,
  ['log-tcp-options'] = true, ['log-tcp-sequence'] = true, ['log-uid'] = true,
  -- reject
  ['reject-with'] = true,
  -- nat
  ['to-source'] = true, ['to-destination'] = true, ['to-ports'] = true,
  -- mark
  ['set-mark'] = true, ['set-xmark'] = true, ['save-mark'] = true, ['restore-mark'] = true,
  -- limit
  limit = true, ['limit-burst'] = true,
  -- icmp
  ['icmp-type'] = true, ['icmpv6-type'] = true,
  -- tcp flags
  ['tcp-flags'] = true,
  -- hashlimit
  ['hashlimit-upto'] = true, ['hashlimit-above'] = true, ['hashlimit-burst'] = true,
  ['hashlimit-name'] = true, ['hashlimit-mode'] = true,
  ['hashlimit-srcmask'] = true, ['hashlimit-dstmask'] = true,
  ['hashlimit-htable-size'] = true, ['hashlimit-htable-max'] = true,
  ['hashlimit-htable-expire'] = true, ['hashlimit-htable-gcinterval'] = true,
  -- recent
  ['name'] = true, ['rsource'] = true, ['rdest'] = true,
  ['seconds'] = true, ['hitcount'] = true, ['rttl'] = true,
  -- owner
  ['uid-owner'] = true, ['gid-owner'] = true,
  -- tos/dscp
  ['set-tos'] = true, ['set-dscp'] = true, ['set-dscp-class'] = true,
  -- misc
  ['match-set'] = true, ['to'] = true, ['clamp-mss-to-pmtu'] = true,
  ['set-mss'] = true,
  -- connlimit
  ['connlimit-above'] = true, ['connlimit-upto'] = true, ['connlimit-mask'] = true,
  -- iprange
  ['src-range'] = true, ['dst-range'] = true,
  -- length
  ['length'] = true,
  -- string
  ['algo'] = true, ['string'] = true,
  -- time
  ['timestart'] = true, ['timestop'] = true, ['days'] = true,
  -- ttl
  ['ttl-eq'] = true, ['ttl-gt'] = true, ['ttl-lt'] = true, ['ttl-set'] = true,
  -- hl
  ['hl-eq'] = true, ['hl-gt'] = true, ['hl-lt'] = true, ['hl-set'] = true,
  -- pkttype
  ['pkt-type'] = true,
  -- statistic
  ['mode'] = true, ['probability'] = true, ['every'] = true, ['packet'] = true,
  -- nfqueue
  ['queue-num'] = true, ['queue-balance'] = true,
  -- quota
  ['quota'] = true,
  -- comment
  ['comment'] = true,
}

M.builtin_vars = {
  ['$DOMAIN'] = true, ['$TABLE'] = true, ['$CHAIN'] = true,
  ['$FILENAME'] = true, ['$FILEBNAME'] = true, ['$DIRNAME'] = true, ['$LINE'] = true,
}

return M
