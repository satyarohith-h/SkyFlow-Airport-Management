import { insert, query, remove, rpc, update } from './supabase.js';

const one = rows => rows?.[0] || null;
const encode = value => encodeURIComponent(String(value));
const airportProjection = 'id,code,name,city,country,timezone,status,terminal_info';

export async function listAirports(search = '') {
  let filter = `?select=${airportProjection}&order=city.asc&limit=500`;
  const term = String(search || '').trim();
  if (term) filter += `&or=(code.ilike.*${encode(term)}*,name.ilike.*${encode(term)}*,city.ilike.*${encode(term)}*,country.ilike.*${encode(term)}*)`;
  return query('airports', filter);
}

export async function listAirlines() {
  return query('airlines', '?select=id,name,code&order=name.asc&limit=500');
}

const toApiFlight = (row, airports, airlines) => {
  const origin = airports.find(item => item.id === row.origin_airport_id) || {};
  const destination = airports.find(item => item.id === row.destination_airport_id) || {};
  const airline = airlines.find(item => item.id === row.airline_id) || {};
  const departure = row.departure_at || '';
  const arrival = row.arrival_at || '';
  const estimated = row.estimated_departure_at || departure;
  return {
    id: row.id, number: row.flight_number, flightNumber: row.flight_number,
    airline: airline.name || row.airline_code || '', airlineCode: row.airline_code || airline.code || '',
    origin: origin.code || '', destination: destination.code || '',
    originAirport: origin, destinationAirport: destination,
    date: departure.slice(0, 10), scheduled: departure.slice(11, 16), departureTime: departure.slice(11, 16),
    arrival: row.arrival_time || arrival.slice(11, 16), arrivalTime: row.arrival_time || arrival.slice(11, 16),
    durationMinutes: Number(row.duration_minutes || 0), stops: Number(row.stops || 0),
    stopsLabel: Number(row.stops || 0) ? `${row.stops} stop(s)` : 'Non-stop',
    travelClass: row.travel_class || 'Economy', fare: Number(row.fare || 0),
    baggageAllowance: row.baggage_allowance || '20 kg', estimated: estimated.slice(11, 16),
    terminal: row.terminal_name || '', gate: row.gate || '', status: row.status,
    aircraft: row.aircraft_model || '', seats: Number(row.seat_capacity || 0),
    booked: Number(row.booked_seats || 0), availableSeats: Math.max(0, Number(row.seat_capacity || 0) - Number(row.booked_seats || 0)),
    simulated: true
  };
};

export async function listFlights(filters = {}) {
  const [airports, airlines] = await Promise.all([query('airports', `?select=${airportProjection}&limit=500`), listAirlines()]);
  const originCode = String(filters.origin || '').split(' ')[0].toUpperCase();
  const destinationCode = String(filters.destination || '').split(' ')[0].toUpperCase();
  const origin = airports.find(item => item.code === originCode || item.city.toLowerCase() === originCode.toLowerCase() || item.name.toLowerCase() === originCode.toLowerCase());
  const destination = airports.find(item => item.code === destinationCode || item.city.toLowerCase() === destinationCode.toLowerCase() || item.name.toLowerCase() === destinationCode.toLowerCase());
  if (originCode && !origin || destinationCode && !destination) return { data: [], count: 0, updatedAt: new Date().toISOString(), simulated: true };
  const conditions = ['select=*', 'order=departure_at.asc', 'limit=500'];
  if (origin) conditions.push(`origin_airport_id=eq.${encode(origin.id)}`);
  if (destination) conditions.push(`destination_airport_id=eq.${encode(destination.id)}`);
  if (filters.date) {
    const start = `${filters.date}T00:00:00.000Z`;
    const end = `${new Date(new Date(start).getTime() + 86400000).toISOString()}`;
    conditions.push(`departure_at=gte.${encode(start)}`, `departure_at=lt.${encode(end)}`);
  }
  if (filters.airline) conditions.push(`airline_code=eq.${encode(String(filters.airline).toUpperCase())}`);
  if (filters.maxPrice !== undefined && filters.maxPrice !== '') conditions.push(`fare=lte.${encode(filters.maxPrice)}`);
  if (filters.travelClass) conditions.push(`travel_class=eq.${encode(filters.travelClass)}`);
  if (filters.status) conditions.push(`status=eq.${encode(filters.status)}`);
  if (filters.departureAfter) conditions.push(`departure_at=gte.${encode(`${filters.date || new Date().toISOString().slice(0, 10)}T${filters.departureAfter}:00.000Z`)}`);
  if (filters.departureBefore) conditions.push(`departure_at=lte.${encode(`${filters.date || new Date().toISOString().slice(0, 10)}T${filters.departureBefore}:59.999Z`)}`);
  if (filters.stops === 'nonstop') conditions.push('stops=eq.0');
  else if (filters.stops === 'connecting') conditions.push('stops=gt.0');
  if (filters.sort === 'cheapest') conditions[1] = 'order=fare.asc';
  if (filters.sort === 'fastest') conditions[1] = 'order=duration_minutes.asc';
  const rows = await query('flights', `?${conditions.join('&')}`);
  return { data: rows.map(row => toApiFlight(row, airports, airlines)), count: rows.length, updatedAt: new Date().toISOString(), simulated: true };
}

export async function getFlight(id) {
  const rows = await query('flights', `?id=eq.${encode(id)}&select=*&limit=1`);
  const row = one(rows);
  if (!row) return null;
  const [airports, airlines] = await Promise.all([query('airports', `?select=${airportProjection}&limit=500`), listAirlines()]);
  return toApiFlight(row, airports, airlines);
}

const lookupFlightRefs = async value => {
  const [airports, airlines, terminals, gates] = await Promise.all([query('airports', '?select=id,code&limit=500'), listAirlines(), query('terminals','?select=id,name,airport_id&limit=1000'), query('gates','?select=id,code,terminal_id&limit=2000')]);
  const origin = airports.find(item => item.code === value.origin);
  const destination = airports.find(item => item.code === value.destination);
  const airline = airlines.find(item => item.code === value.airlineCode);
  const terminal = terminals.find(item => item.name === value.terminal && (!origin || item.airport_id === origin.id));
  const gate = gates.find(item => item.code === value.gate && item.terminal_id === terminal?.id);
  if (value.gate && (!terminal || !gate)) throw Object.assign(new Error('Terminal or gate is not configured for the origin airport'), { status: 422 });
  return { origin, destination, airline, terminal, gate };
};

const toDbFlight = (value, refs, actorId) => ({
  flight_number: value.number,
  airline_id: refs.airline?.id || null,
  airline_code: value.airlineCode,
  origin_airport_id: refs.origin?.id || null,
  destination_airport_id: refs.destination?.id || null,
  departure_at: `${value.date}T${value.scheduled}:00.000Z`,
  arrival_at: value.arrival ? `${value.date}T${value.arrival}:00.000Z` : null,
  estimated_departure_at: value.estimated ? `${value.date}T${value.estimated}:00.000Z` : null,
  arrival_time: value.arrival || null,
  duration_minutes: value.durationMinutes,
  stops: value.stops,
  travel_class: value.travelClass,
  fare: value.fare,
  baggage_allowance: value.baggageAllowance,
  terminal_name: value.terminal,
  terminal_id: refs.terminal?.id || null,
  gate_id: refs.gate?.id || null,
  gate: value.gate || null,
  seat_capacity: value.seats,
  status: value.status,
  aircraft_model: value.aircraft || null,
  changed_by: actorId || null
});

export async function createFlight(value, actorId) {
  const refs = await lookupFlightRefs(value);
  if (!refs.origin || !refs.destination) throw Object.assign(new Error('Origin or destination airport is not configured in Supabase'), { status: 422 });
  const created = one(await insert('flights', toDbFlight(value, refs, actorId)));
  return getFlight(created.id);
}

export async function updateFlight(id, value, actorId) {
  const previous = one(await query('flights', `?id=eq.${encode(id)}&select=id,status&limit=1`));
  if (!previous) return null;
  const refs = await lookupFlightRefs(value);
  if (!refs.origin || !refs.destination) throw Object.assign(new Error('Origin or destination airport is not configured in Supabase'), { status: 422 });
  const rows = await update('flights', `id=eq.${encode(id)}`, toDbFlight(value, refs, actorId));
  return rows?.length ? getFlight(id) : null;
}

export async function patchFlight(id, values, actorId) {
  const previous = one(await query('flights', `?id=eq.${encode(id)}&select=id,status&limit=1`));
  if (!previous) return null;
  const fields = {};
  if (values.estimated !== undefined) fields.estimated_departure_at = values.estimated ? `${new Date().toISOString().slice(0, 10)}T${values.estimated}:00.000Z` : null;
  if (values.gate !== undefined) fields.gate = values.gate || null;
  if (values.status !== undefined) fields.status = values.status;
  if (values.terminal !== undefined) fields.terminal_name = values.terminal;
  fields.changed_by = actorId || null;
  const rows = await update('flights', `id=eq.${encode(id)}`, fields);
  return rows?.length ? getFlight(id) : null;
}

export async function deleteFlight(id) {
  const bookings = await query('bookings', `?flight_id=eq.${encode(id)}&select=id&limit=1`);
  if (bookings.length) throw Object.assign(new Error('Flight has bookings and cannot be deleted'), { status: 409 });
  const rows = await remove('flights', `id=eq.${encode(id)}`);
  return rows?.length > 0;
}

export async function getFlightHistory(id) {
  return query('flight_status_history', `?flight_id=eq.${encode(id)}&select=*&order=created_at.desc&limit=200`);
}

export async function listSeats(flightId) {
  const [seats, assigned] = await Promise.all([
    query('seats', `?flight_id=eq.${encode(flightId)}&select=id,seat_number,class&order=seat_number.asc&limit=600`),
    query('booking_passengers', `?select=seat_id,booking:bookings!inner(flight_id,status)&booking.flight_id=eq.${encode(flightId)}&booking.status=not.in.(Cancelled,Refunded)&limit=600`)
  ]);
  const occupied = new Set(assigned.map(item => item.seat_id));
  return seats.map(item => ({ seat: item.seat_number, status: occupied.has(item.id) ? 'occupied' : 'available', class: item.class }));
}

const toApiBooking = row => {
  const passengers = (row.booking_passengers || []).map(item => ({ id:item.id,fullName:item.full_name,dateOfBirth:item.date_of_birth,contactEmail:item.contact_email,contactPhone:item.contact_phone,documentType:item.document_type,documentLast4:item.document_last4,seat:item.seat?.seat_number || '' }));
  const seats = passengers.map(item => item.seat).filter(Boolean);
  const payment = row.booking_payments?.[0];
  return { id:row.id,pnr:row.pnr,userId:row.user_id,flightId:row.flight_id,passenger:passengers[0]?.fullName || '',passengers,seats,seat:seats[0] || '',status:row.status,contactEmail:row.contact_email,contactPhone:row.contact_phone,baseFare:Number(row.base_fare || 0),taxes:Number(row.taxes || 0),baggageAddons:Number(row.baggage_addons || 0),totalAmount:Number(row.total_amount || 0),paymentStatus:row.payment_status,idempotencyKey:row.idempotency_key,checkedIn:Boolean(row.check_ins?.length),boardingPasses:row.boarding_passes || [],baggage:row.baggage?.[0]?.tag_number || '',baggageStatus:row.baggage?.[0]?.status || 'Not registered',createdAt:row.created_at,payment:payment ? {status:payment.status,amount:Number(payment.amount),method:payment.method} : null};
};

const bookingProjection = '*,booking_passengers(id,full_name,seat_id,date_of_birth,contact_email,contact_phone,document_type,document_last4,seat:seats(seat_number)),baggage(id,tag_number,status),check_ins(id,status),boarding_passes(id,pass_reference,qr_payload,status),booking_payments(amount,status,method)';

export async function listBookings(user, search = '') {
  const filters = [`select=${bookingProjection}`];
  if (user.role === 'passenger') filters.push(`user_id=eq.${encode(user.id)}`);
  if (search) filters.push(`pnr=ilike.*${encode(search)}*`);
  filters.push('order=created_at.desc', 'limit=200');
  const rows = await query('bookings', `?${filters.join('&')}`);
  return rows.map(toApiBooking);
}

export async function getBooking(id, user) {
  const filters = [`id=eq.${encode(id)}`, `select=${bookingProjection}`, 'limit=1'];
  if (user.role === 'passenger') filters.push(`user_id=eq.${encode(user.id)}`);
  const row = one(await query('bookings', `?${filters.join('&')}`));
  return row ? toApiBooking(row) : null;
}

export async function createBooking(input, userId) {
  return rpc('create_booking_atomic', {
    p_user_id: userId,
    p_flight_id: input.flightId,
    p_passengers: input.passengers,
    p_seats: input.seats,
    p_contact_email: input.contactEmail || null,
    p_contact_phone: input.contactPhone || null,
    p_idempotency_key: input.idempotencyKey
  });
}
