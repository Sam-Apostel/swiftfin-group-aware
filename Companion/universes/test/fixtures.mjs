// A tiny slice of Wikidata, shaped like what the Wikidata client returns.

export const entity = (id, name, types, extra = {}) => ({ id, name, description: null, types, wikipedia: null, image: null, ids: {}, ...extra })

export function addamsAndAvatar() {
  const entities = new Map(
    [
      entity('Q1', 'Wednesday', ['Q5398426'], { start: '2022-11-23T00:00:00Z', ids: { tmdbTv: '119051' } }),
      entity('Q2', 'The Addams Family', ['Q11424'], { published: '1991-11-22T00:00:00Z', ids: { tmdbMovie: '2907' } }),
      entity('Q3', 'Addams Family Values', ['Q11424'], { published: '1993-11-19T00:00:00Z', ids: { tmdbMovie: '2758' } }),
      entity('Q10', 'The Addams Family universe', ['Q559618']),
      entity('Q11', 'Wednesday Addams', ['Q15773347']),
      entity('Q20', 'Avatar: The Last Airbender', ['Q117467246'], { start: '2005-02-21T00:00:00Z', ids: { tmdbTv: '246' } }),
      entity('Q21', 'The Rise of Kyoshi', ['Q7725634'], { published: '2019-07-16T00:00:00Z', ids: { isbn: '978-1-4197-3504-2' } }),
      entity('Q22', 'The Legend of Korra', ['Q581714'], { start: '2012-04-14T00:00:00Z', ids: { tmdbTv: '33880' } }),
      entity('Q30', 'Avatar franchise', ['Q196600']),
      entity('Q40', 'Episode 1', ['Q21191270']),
      entity('Q50', 'Ancient Rome', ['Q1307214'], { start: '-0753-01-01T00:00:00Z', end: '0476-01-01T00:00:00Z' }),
      entity('Q51', 'Rome: Rise and Fall', ['Q93204'], { published: '2006-01-01T00:00:00Z' }),
      entity('Q52', 'Roman Empire doc', ['Q93204'], { published: '2016-01-01T00:00:00Z' }),
    ].map((e) => [e.id, e]),
  )
  const edges = new Map([
    ['Q1', [{ prop: 'P1434', target: 'Q10' }, { prop: 'P674', target: 'Q11' }]],
    ['Q2', [{ prop: 'P1434', target: 'Q10' }, { prop: 'P674', target: 'Q11' }, { prop: 'P156', target: 'Q3' }]],
    ['Q3', [{ prop: 'P1434', target: 'Q10' }, { prop: 'P155', target: 'Q2' }]],
    ['Q20', [{ prop: 'P8345', target: 'Q30' }, { prop: 'P156', target: 'Q22' }]],
    ['Q51', [{ prop: 'P921', target: 'Q50' }]],
    ['Q52', [{ prop: 'P921', target: 'Q50' }]],
  ])
  const library = [
    { id: 'jf-wed', type: 'Series', name: 'Wednesday', genres: ['Comedy'], ids: { tmdb: '119051' }, premiereDate: '2022-11-23', year: 2022 },
    { id: 'jf-af', type: 'Movie', name: 'The Addams Family', genres: ['Comedy', 'Horror'], ids: { tmdb: '2907' }, premiereDate: '1991-11-22', year: 1991 },
    { id: 'jf-atla', type: 'Series', name: 'Avatar: The Last Airbender', genres: ['Animation'], ids: { tmdb: '246' }, premiereDate: '2005-02-21', year: 2005 },
    { id: 'jf-rome1', type: 'Series', name: 'Rome: Rise and Fall', genres: ['Documentary'], ids: { tmdb: '9001' }, premiereDate: '2006-01-01', year: 2006 },
    { id: 'jf-rome2', type: 'Movie', name: 'Roman Empire doc', genres: ['Documentary'], ids: { tmdb: '9002' }, premiereDate: '2016-01-01', year: 2016 },
    { id: 'jf-kz', type: 'Episode', name: 'The First Civilizations', seriesName: 'Kurzgesagt', genres: [], ids: { youtube: 'abcDEF12345' }, premiereDate: '2024-01-01', year: 2024, overview: '' },
    { id: 'jf-hc1', type: 'Episode', name: 'Hermitcraft 11: Episode 1', seriesName: 'Grian', genres: [], ids: { youtube: 'AAAAAAAAAA1' }, premiereDate: '2025-03-01', year: 2025 },
    { id: 'jf-hc2', type: 'Episode', name: 'HermitCraft Season 11 Ep 1', seriesName: 'Mumbo Jumbo', genres: [], ids: { youtube: 'BBBBBBBBBB2' }, premiereDate: '2025-03-02', year: 2025 },
  ]
  const resolved = new Map([['jf-wed', 'Q1'], ['jf-af', 'Q2'], ['jf-atla', 'Q20'], ['jf-rome1', 'Q51'], ['jf-rome2', 'Q52']])
  const members = new Map([
    ['Q10', ['Q1', 'Q2', 'Q3']],
    ['Q30', ['Q20', 'Q21', 'Q22', 'Q40']],
  ])
  return { entities, edges, library, resolved, members }
}
