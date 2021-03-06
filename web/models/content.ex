defmodule IdeaZone.Content do
  @moduledoc """
  Content is the main resource of the application.

  ## Fields
    - `language` is used to select the search configuration to apply
      on the content when performing PostgreSQL fulltext search.

  ## Associations
  - type (`ContentType`),
  - comments,
  - votes.

  ## Status
    - `new`
    - `in_progress`
    - `solved`

  ## TODO
    - add validation on status
  """

  use IdeaZone.Web, :model
  alias IdeaZone.Repo
  alias IdeaZone.Vote

  schema "contents" do
    field :label, :string
    field :description, :string
    field :hidden, :boolean, default: false
    field :official_answer, :string
    field :language, :string
    field :status, :string
    field :vote_score, :integer, virtual: true
    field :vote_for_current_user, :map, virtual: true

    belongs_to :type, IdeaZone.ContentType

    has_many :comments, IdeaZone.Comment, on_delete: :delete_all
    has_many :votes, Vote, on_delete: :delete_all

    timestamps
  end

  @required_fields ~w(label description language type_id status)
  @optional_fields ~w(official_answer hidden)

  @doc """
  Creates a changeset based on the `model` and `params`.

  If no params are provided, an invalid changeset is returned
  with no validation performed.
  """
  def changeset(model, params \\ :empty) do
    model
    |> cast(params, @required_fields, @optional_fields)
  end

  @doc """
  Query contents doing good-enough full-text search using PostgreSQL
  features. Followed [this article][1] and [this one][2] for indexing.

  ## Parameters
    - `search_terms`: array of `Content` record ids.

  ## Query details
    - Not using `to_tsquery` with the query terms because it removes
      the stop words. Since we want partial matches (from the search
      term beginning - `search_term:*`), partial words may be removed
      from the query if we using it.
    - `::regconfig` indicates the preceding value (`contents.language`)
      is intended to be used as config. See the `...setup_content_search`
      migration for available text search configurations.

  ## TODO
    - generalize Ecto custom SQL queries (see [this SO question][2])
    - see if fragments may be used instead of a full SQL-query

  [1]: http://rachbelaid.com/postgres-full-text-search-is-good-enough/
  [2]: https://blog.lateral.io/2015/05/full-text-search-in-milliseconds-with-postgresql/
  [3]: http://stackoverflow.com/questions/27751216/how-to-use-raw-sql-with-ecto-repo)
  """
  def search(search_terms) do
    sql_terms = search_terms |> Enum.map(fn(s) -> "#{s}:*" end) |> Enum.join(" | ")
    query = """
      SELECT contents.id
      FROM contents
      WHERE
        ( ts_rank(contents.tsv, '#{sql_terms}') <> 0
          OR ts_rank(contents.tsv, to_tsquery('#{sql_terms}')) <> 0 )
      ORDER BY ts_rank(contents.tsv, '#{sql_terms}') DESC
      LIMIT 10;
    """
    { :ok, response } = Ecto.Adapters.SQL.query(Repo, query, [])
    response.rows |> Enum.flat_map(&(&1))
  end

  @doc """
  Assumes content's votes have been preloaded.
  """
  def calculate_vote_score(content) do
    vote_score = content.votes
      |> Enum.reduce(0, fn(vote, acc) -> acc + score_for_vote_type(vote.vote_type) end)
    %{content | vote_score: vote_score}
  end

  @doc """
  Assumes content's votes have been preloaded.

  ## Params
    - `content`
    - `session_token`: String, session token for the user
  """
  def calculate_vote_for_user(content, session_token) do
    %{content | vote_for_current_user: get_vote_for_user(content, session_token)}
  end

  @doc """
  Assumes content's votes have been preloaded.
  """
  def get_vote_for_user(content, user_session_token) do
    content.votes
      |> Enum.find(nil, fn(vote) ->
          vote.user_session_token == user_session_token
        end)
  end

  defp score_for_vote_type("for"), do: 1
  defp score_for_vote_type("against"), do: -1
  defp score_for_vote_type(_), do: 0
end
