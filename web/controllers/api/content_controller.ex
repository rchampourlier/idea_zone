defmodule IdeaZone.API.ContentController do
  use IdeaZone.Web, :controller
  alias IdeaZone.Content

  import Ecto.Query, only: [from: 2]

  def index(conn, %{"filter" => ""}) do
    user_session_token = get_session(conn, :session_token)
    contents = fetch_displayed_contents(user_session_token)
    conn
      |> assign(:contents, contents)
      |> render("index.json")
  end

  def index(conn, %{"filter" => filter}) do
    user_session_token = get_session(conn, :session_token)
    search_terms = filter |> String.split |> Enum.reject(fn(s) -> String.length(s) == 0 end)
    contents = fetch_with_filter(search_terms, user_session_token)
    conn
      |> assign(:contents, contents)
      |> render("index.json")
  end

  def index(conn, _params) do
    user_session_token = get_session(conn, :session_token)
    contents = fetch_displayed_contents(user_session_token)
    conn
      |> assign(:contents, contents)
      |> render("index.json")
  end

  defp fetch_with_filter(search_terms, user_session_token) do
    ids = Content.search(search_terms)
    query = from c in Content, where: c.id in ^ids
    Repo.all(query)
      |> Repo.preload([:votes, :type])
      |> map_vote_scores
      |> map_vote_type_for_current_user(user_session_token)
  end

  defp fetch_displayed_contents(user_session_token) do
    query = from c in Content, where: c.hidden == false
    Repo.all(query)
      |> Repo.preload([:votes, :type])
      |> map_vote_scores
      |> map_vote_type_for_current_user(user_session_token)
      |> sort_on_vote_scores
  end

  defp map_vote_scores(contents) do
    contents |> Enum.map(&(Content.calculate_vote_score(&1)))
  end

  defp map_vote_type_for_current_user(contents, user_session_token) do
    contents |> Enum.map(&(Content.calculate_vote_type_for_current_user(&1, user_session_token)))
  end

  defp sort_on_vote_scores(contents) do
    contents |> Enum.sort(fn(a, b) -> a.vote_score > b.vote_score end)
  end
end