defmodule FormentationDemo.LiveHelpers do
  @moduledoc "Handler plumbing shared by the demo LiveViews."

  alias Formentation.Form

  @doc """
  The decoded candidate of a fully valid submitted form, or nil —
  what the demo renders in its `<pre id="decoded-candidate">`.
  """
  def submitted_candidate(form_state) do
    case {Form.issues(form_state), Form.candidate(form_state)} do
      {[], {:ok, candidate}} -> candidate
      _invalid_or_none -> nil
    end
  end
end
