defmodule Formentation.FreePortTest do
  use ExUnit.Case, async: true

  doctest Formentation.FreePort

  alias Formentation.FreePort

  test "returns a port in the unprivileged range" do
    port = FreePort.pick()

    assert is_integer(port)
    assert port > 1024
    assert port <= 65_535
  end

  test "returns a port that is actually bindable afterwards" do
    port = FreePort.pick()

    assert {:ok, socket} = :gen_tcp.listen(port, ip: {127, 0, 0, 1})
    assert :ok = :gen_tcp.close(socket)
  end

  test "successive picks are not all identical" do
    # The kernel cycles through its ephemeral range rather than reissuing
    # the port it just released, which is what makes concurrent runs safe.
    # Weak on purpose: this pins the environmental premise (the kernel does
    # vary the port), not any specific cycling order — a sequence like
    # A,B,A,B,A would still satisfy it.
    ports = Enum.map(1..5, fn _ -> FreePort.pick() end)

    assert match?([_, _ | _], Enum.uniq(ports))
  end
end
