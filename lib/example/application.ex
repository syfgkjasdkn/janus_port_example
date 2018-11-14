defmodule Example.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = [
      {Janus.Socket,
       config: %Janus.Config{
         binary_path: "/opt/janus/bin/janus",
         client_sock: "/home/vagrant/elixir.sock",
         janus_sock: "/home/vagrant/janus.sock"
       }},
      %{
        id: :elli,
        start: {:elli, :start_link, [[callback: Example.Handler, port: 4000]]}
      }
    ]

    opts = [strategy: :one_for_one, name: Example.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
