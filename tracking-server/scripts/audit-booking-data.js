import 'dotenv/config';
import { firestore } from '../src/firebase-auth.js';

const collections = await firestore.listCollections();
const report = [];
for (const collection of collections) {
  const snapshot = await collection.count().get();
  report.push({ collection: collection.id, documents: snapshot.data().count });
}
console.table(report.sort((a, b) => a.collection.localeCompare(b.collection)));
