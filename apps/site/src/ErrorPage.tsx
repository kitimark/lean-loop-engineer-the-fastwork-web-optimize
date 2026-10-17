/** Unknown ids and violated requires/conflicts are an error page, never a fallback (PLAN 6.3). */
export function ErrorPage({ errors }: { errors: string[] }) {
  return (
    <main data-fw="config-error">
      <h1>Invalid flag configuration</h1>
      <ul>
        {errors.map((e) => (
          <li key={e}>{e}</li>
        ))}
      </ul>
    </main>
  );
}
