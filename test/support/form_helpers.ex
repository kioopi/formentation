defmodule Formentation.Test.FormHelpers do
  @moduledoc false

  alias Formentation.Form

  def submitted_form(%Form{} = form, params) when is_map(params) do
    form
    |> Form.submit(params)
    |> unwrap_submitted_form()
  end

  def unwrap_submitted_form({:ok, _candidate, %Form{} = form}), do: form
  def unwrap_submitted_form({:error, %Form{} = form}), do: form
end
