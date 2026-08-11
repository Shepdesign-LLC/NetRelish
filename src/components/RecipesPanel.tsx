import { useCallback, useEffect, useState } from "react";
import {
  deleteRecipe,
  listRecipes,
  updateRecipeSteps,
  type Recipe,
} from "../lib/db";
import { parseSteps } from "../lib/recipes";

interface Props {
  jarId: string;
  refreshToken: number;
  recording: boolean;
  onSaveRecording(name: string): Promise<void>;
  onDiscardRecording(): void;
  onRun(recipe: Recipe): void;
}

function stepCount(recipe: Recipe): number {
  try {
    const parsed = JSON.parse(recipe.steps) as unknown;
    return Array.isArray(parsed) ? parsed.length : 0;
  } catch {
    return 0;
  }
}

/** The right-rail Recipes card: run them, read their JSON, edit it by hand
 *  (§11 says the JSON must stay readable and hand-editable — so it's right
 *  here). Recording starts from the jar header's pill. */
export default function RecipesPanel({
  jarId,
  refreshToken,
  recording,
  onSaveRecording,
  onDiscardRecording,
  onRun,
}: Props) {
  const [recipes, setRecipes] = useState<Recipe[]>([]);
  const [editing, setEditing] = useState<string | null>(null);
  const [draft, setDraft] = useState("");
  const [problem, setProblem] = useState<string | null>(null);
  const [saveName, setSaveName] = useState("");

  const refresh = useCallback(async () => {
    setRecipes(await listRecipes(jarId));
  }, [jarId]);

  useEffect(() => {
    void refresh();
  }, [refresh, refreshToken]);

  const saveEdit = useCallback(
    async (id: string) => {
      const parsed = parseSteps(draft);
      if (typeof parsed === "string") {
        setProblem(parsed);
        return;
      }
      await updateRecipeSteps(id, JSON.stringify(parsed, null, 2));
      setProblem(null);
      setEditing(null);
      await refresh();
    },
    [draft, refresh],
  );

  return (
    <div className="nr-recipes">
      <div className="nr-recipes__head">
        <span className="nr-recipes__title">Recipes</span>
        <span className="nr-recipes__runs">⌘R runs</span>
      </div>

      {recording && (
        <>
          <p className="nr-recipes__hint">
            Recording. Work normally — new tabs, addresses you enter, and ⌘J
            become steps. Save from here when the shape is right.
          </p>
          <div className="nr-recipes__bar">
            <input
              placeholder="Name this recipe"
              aria-label="Recipe name"
              value={saveName}
              onChange={(e) => setSaveName(e.target.value)}
            />
            <button
              type="button"
              disabled={!saveName.trim()}
              onClick={() => {
                void onSaveRecording(saveName.trim()).then(() => {
                  setSaveName("");
                  void refresh();
                });
              }}
            >
              Save as Recipe
            </button>
            <button type="button" onClick={onDiscardRecording}>
              Discard
            </button>
          </div>
        </>
      )}

      {recipes.length > 0 && (
        <ul className="nr-recipes__list">
          {recipes.map((r) => (
            <li key={r.id} className="nr-recipes__row">
              <span className="nr-recipes__name">{r.name}</span>
              <button type="button" onClick={() => onRun(r)}>
                Run
              </button>
              <span className="nr-recipes__steps">
                {stepCount(r)} step{stepCount(r) === 1 ? "" : "s"}
              </span>
              <button
                type="button"
                aria-expanded={editing === r.id}
                onClick={() => {
                  if (editing === r.id) {
                    setEditing(null);
                  } else {
                    setEditing(r.id);
                    setDraft(r.steps);
                    setProblem(null);
                  }
                }}
              >
                JSON
              </button>
              <button
                type="button"
                onClick={() => {
                  void deleteRecipe(r.id).then(refresh);
                }}
              >
                Delete
              </button>
              {editing === r.id && (
                <div className="nr-recipes__editor">
                  <textarea
                    aria-label={`Steps for ${r.name}`}
                    value={draft}
                    rows={10}
                    spellCheck={false}
                    onChange={(e) => setDraft(e.target.value)}
                  />
                  {problem && <p className="nr-recipes__problem">{problem}</p>}
                  <button type="button" onClick={() => void saveEdit(r.id)}>
                    Save steps
                  </button>
                </div>
              )}
            </li>
          ))}
        </ul>
      )}

      <p className="nr-recipes__hint">
        Recipes are recorded, not authored — work normally, then Save as
        Recipe.
      </p>
    </div>
  );
}
