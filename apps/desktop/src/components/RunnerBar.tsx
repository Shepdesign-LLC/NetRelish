import { stepLabel, type RecipeStep } from "../lib/recipes";

interface Props {
  recipeName: string;
  steps: RecipeStep[];
  index: number;
  finished: boolean;
  onBack(): void;
  onSkip(): void;
  onDone(): void;
  onFinish(): void;
  onCancel(): void;
}

/**
 * The recipe runner: a band of chrome, never an overlay — the stage
 * shrinks beneath it, so it stays visible over live pages. Action steps
 * run themselves; task steps wait for a human.
 */
export default function RunnerBar({
  recipeName,
  steps,
  index,
  finished,
  onBack,
  onSkip,
  onDone,
  onFinish,
  onCancel,
}: Props) {
  const step = steps[index];
  const isTask = step?.kind === "task";

  return (
    <div className="nr-runner" role="region" aria-label={`Recipe: ${recipeName}`}>
      <span className="nr-runner__which">
        {recipeName} · {Math.min(index + 1, steps.length)}/{steps.length}
      </span>
      <span className="nr-runner__step" aria-live="polite">
        {finished ? "Recipe finished" : step ? stepLabel(step) : ""}
      </span>
      {!finished && (
        <>
          <button type="button" onClick={onBack} disabled={index <= 0}>
            Back
          </button>
          {isTask && (
            <>
              <button type="button" onClick={onSkip}>
                Skip
              </button>
              <button type="button" className="nr-runner__done" onClick={onDone}>
                Done
              </button>
            </>
          )}
        </>
      )}
      <button type="button" className="nr-runner__done" onClick={onFinish}>
        Finish
      </button>
      {!finished && (
        <button type="button" onClick={onCancel}>
          Cancel
        </button>
      )}
    </div>
  );
}
