locals {
  realms = [
    {
      name     = "johan"
      hostname = "johan.${local.hostname}"
      users = [{
        username   = "johan"
        first_name = "Johan"
        last_name  = "Vandeweerd"
        email      = "johan@engine31.io"
      }]
    },
    {
      name     = "frans"
      hostname = "frans.${local.hostname}"
      users = [{
        username   = "frans"
        first_name = "Frans"
        last_name  = "Guelinckx"
        email      = "frans@engine31.io"
      }]
    }
  ]
}
