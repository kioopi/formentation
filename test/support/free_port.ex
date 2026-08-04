defmodule Formentation.FreePort do
  @moduledoc """
  Asks the operating system for a TCP port nothing is using.

  The browser-real lane (`mix test.browser`) is the only part of the
  suite that binds a real socket. Hardcoding its port made two
  concurrent runs collide and invited a `PORT=...` prefix on every
  command; letting the kernel choose removes both.
  """

  @doc """
  Returns a port number the OS handed out for an ephemeral bind.

  Listens on port 0 on the loopback interface, reads back the port the
  kernel assigned, and closes the socket so the caller can bind it.

  There is a small window between the close and the caller's bind in
  which another process could take the port. Losing that race surfaces
  as a loud failure to start the endpoint, not as silent misbehaviour.

  ## Examples

      iex> port = Formentation.FreePort.pick()
      iex> port > 1024 and port <= 65_535
      true

  """
  @spec pick() :: :inet.port_number()
  def pick do
    {:ok, socket} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)

    port
  end
end
