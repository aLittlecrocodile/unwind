interface HealthActionsProps {
  onDrinkWater(): void
  onStandUp(): void
}

export function HealthActions({ onDrinkWater, onStandUp }: HealthActionsProps): React.JSX.Element {
  return (
    <section className="health-actions">
      <button type="button" onClick={onStandUp}>我起来了</button>
      <button type="button" onClick={onDrinkWater}>喝水了</button>
    </section>
  )
}
