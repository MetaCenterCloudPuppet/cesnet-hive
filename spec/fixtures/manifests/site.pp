$realm = ''

class{'hadoop':
  realm => $realm,
}

class{'hive':
  db    => 'mysql',
  #db    => 'postgresql',
  realm => $realm,
}
